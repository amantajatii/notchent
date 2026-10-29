import Foundation
import CryptoKit
import Network

/// Public Codex control-socket WebSocket; never records message contents.
actor CodexSocket {
    enum Failure: Error, Equatable { case closed, invalidHandshake, invalidFrame, oversized, timedOut, rpcRejected }
    nonisolated let messages: AsyncStream<Data>
    private let output: AsyncStream<Data>.Continuation
    private var connection: NWConnection?
    private var connectWaiter: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private var calls: [Int: CheckedContinuation<Data, Error>] = [:]
    private var callTimeouts: [Int: Task<Void, Never>] = [:]
    private var nextID = 0
    private var handshake = Data()
    private var key = ""
    private var ready = false
    private var finished = false
    private var codec = CodexWebSocketCodec()

    init() {
        let stream = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(256))
        messages = stream.stream; output = stream.continuation
    }
    func connect(path: URL) async throws {
        guard connection == nil, !finished else { throw Failure.closed }
        key = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString()
        let connection = NWConnection(to: .unix(path: path.path), using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in Task { await self?.stateChanged(state) } }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectWaiter = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                await self?.fail(Failure.timedOut)
            }
            connection.start(queue: DispatchQueue(label: "IslandMac.CodexSocket"))
        }
    }
    func call(_ method: String, params: Data) async throws -> Data {
        guard ready, !finished else { throw Failure.closed }
        guard params.count <= CodexWebSocketCodec.maximumBytes else { throw Failure.oversized }
        let parameters = try JSONSerialization.jsonObject(with: params)
        guard parameters is [String: Any] else { throw Failure.invalidFrame }
        nextID += 1
        let id = nextID
        let request = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": parameters])
        guard request.count <= CodexWebSocketCodec.maximumBytes else { throw Failure.oversized }
        return try await withCheckedThrowingContinuation { continuation in
            calls[id] = continuation
            callTimeouts[id] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                await self?.fail(Failure.timedOut)
            }
            Task { [weak self] in
                guard let self else { return }
                do { try await self.write(CodexWebSocketCodec.clientFrame(request)) }
                catch { await self.fail(error) }
            }
        }
    }
    func notify(_ method: String) async throws {
        guard ready, !finished else { throw Failure.closed }
        let notification = try JSONSerialization.data(withJSONObject: ["method": method])
        try await write(CodexWebSocketCodec.clientFrame(notification))
    }
    func respond(id: Data, result: Data) async throws {
        guard ready, !finished else { throw Failure.closed }
        guard id.count <= CodexWebSocketCodec.maximumBytes, result.count <= CodexWebSocketCodec.maximumBytes else { throw Failure.oversized }
        let identifier = try JSONSerialization.jsonObject(with: id, options: .fragmentsAllowed)
        guard identifier is String || Self.integerID(identifier) != nil else { throw Failure.invalidFrame }
        let result = try JSONSerialization.jsonObject(with: result, options: .fragmentsAllowed)
        let response = try JSONSerialization.data(withJSONObject: ["id": identifier, "result": result])
        guard response.count <= CodexWebSocketCodec.maximumBytes else { throw Failure.oversized }
        try await write(CodexWebSocketCodec.clientFrame(response))
    }
    func close() { fail(Failure.closed) }

    private func stateChanged(_ state: NWConnection.State) async {
        guard !finished else { return }
        switch state {
        case .ready:
            receiveNext()
            let request = "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n"
            do { try await write(Data(request.utf8)) } catch { fail(error) }
        case .failed(let error): fail(error)
        case .cancelled: fail(Failure.closed)
        default: break
        }
    }
    private func receiveNext() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            Task { await self?.receive(data, complete: complete, error: error) }
        }
    }
    private func receive(_ data: Data?, complete: Bool, error: NWError?) async {
        guard !finished else { return }
        if let error { fail(error); return }
        do {
            var bytes = data ?? Data()
            if !ready {
                handshake.append(bytes)
                guard let end = handshake.range(of: Data("\r\n\r\n".utf8)) else {
                    guard handshake.count <= 16384, !complete else { throw Failure.invalidHandshake }
                    receiveNext(); return
                }
                guard end.upperBound <= 16384 else { throw Failure.invalidHandshake }
                try CodexWebSocketCodec.validateHandshake(Data(handshake[..<end.upperBound]), key: key)
                bytes = Data(handshake[end.upperBound...]); handshake.removeAll()
                ready = true; timeout?.cancel(); timeout = nil
                connectWaiter?.resume(); connectWaiter = nil
            }
            for event in try codec.append(bytes) {
                switch event {
                case .text(let message): try receiveMessage(message)
                case .ping(let payload): try await write(CodexWebSocketCodec.clientFrame(payload, opcode: 10))
                case .close:
                    try await write(CodexWebSocketCodec.clientFrame(Data(), opcode: 8))
                    throw Failure.closed
                }
            }
            if complete { fail(Failure.closed) } else { receiveNext() }
        } catch { fail(error) }
    }
    private static func integerID(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              String(cString: number.objCType) != "d", String(cString: number.objCType) != "f" else { return nil }
        return Int(exactly: number.int64Value)
    }
    private func receiveMessage(_ data: Data) throws {
        guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalidFrame }
        if message["method"] == nil, let id = Self.integerID(message["id"]), let continuation = calls.removeValue(forKey: id) {
            callTimeouts.removeValue(forKey: id)?.cancel()
            if let result = message["result"] {
                continuation.resume(returning: try JSONSerialization.data(withJSONObject: result, options: .fragmentsAllowed))
            } else { continuation.resume(throwing: Failure.rpcRejected) }
        } else {
            switch output.yield(data) {
            case .enqueued: break
            case .dropped: throw Failure.oversized
            case .terminated: throw Failure.closed
            @unknown default: throw Failure.closed
            }
        }
    }
    private func write(_ data: Data) async throws {
        guard let connection, !finished else { throw Failure.closed }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
    private func fail(_ error: Error) {
        guard !finished else { return }
        finished = true; ready = false
        timeout?.cancel(); timeout = nil
        connectWaiter?.resume(throwing: error); connectWaiter = nil
        for continuation in calls.values { continuation.resume(throwing: error) }
        calls.removeAll()
        for task in callTimeouts.values { task.cancel() }; callTimeouts.removeAll()
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        output.finish()
    }
}

/// Strict uncompressed text-only RFC 6455 framing for the local Codex JSON transport.
struct CodexWebSocketCodec {
    enum Event: Equatable { case text(Data), ping(Data), close }
    static let maximumBytes = 4 * 1024 * 1024
    private var buffer: [UInt8] = []
    private var fragment: [UInt8]?
    static func validateHandshake(_ data: Data, key: String) throws {
        guard let text = String(data: data, encoding: .utf8) else { throw CodexSocket.Failure.invalidHandshake }
        let lines = text.components(separatedBy: "\r\n")
        guard lines.first?.split(separator: " ").prefix(2) == ["HTTP/1.1", "101"] else { throw CodexSocket.Failure.invalidHandshake }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { throw CodexSocket.Failure.invalidHandshake }
            let name = pair[0].lowercased()
            guard headers[name] == nil else { throw CodexSocket.Failure.invalidHandshake }
            headers[name] = pair[1].trimmingCharacters(in: .whitespaces)
        }
        let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
        guard headers["upgrade"]?.lowercased() == "websocket",
              headers["connection"]?.lowercased().split(separator: ",").contains(where: { $0.trimmingCharacters(in: .whitespaces) == "upgrade" }) == true,
              headers["sec-websocket-accept"] == accept,
              headers["sec-websocket-extensions"] == nil else { throw CodexSocket.Failure.invalidHandshake }
    }
    static func clientFrame(_ data: Data, opcode: UInt8 = 1) -> Data {
        var header: [UInt8] = [0x80 | opcode]
        if data.count < 126 { header.append(0x80 | UInt8(data.count)) }
        else if data.count <= Int(UInt16.max) { header += [0xfe, UInt8(data.count >> 8), UInt8(data.count & 255)] }
        else {
            header.append(0xff)
            header += (0..<8).reversed().map { UInt8((UInt64(data.count) >> ($0 * 8)) & 255) }
        }
        let mask = (0..<4).map { _ in UInt8.random(in: .min ... .max) }
        return Data(header + mask + data.enumerated().map { $0.element ^ mask[$0.offset % 4] })
    }
    mutating func append(_ data: Data) throws -> [Event] {
        guard data.count <= Self.maximumBytes + 14, buffer.count <= Self.maximumBytes + 14 else { throw CodexSocket.Failure.oversized }
        buffer.append(contentsOf: data)
        var events: [Event] = []
        var offset = 0
        while buffer.count - offset >= 2 {
            let a = buffer[offset], b = buffer[offset + 1], opcode = a & 15, final = a & 128 != 0
            guard a & 0x70 == 0, b & 128 == 0, [0, 1, 8, 9, 10].contains(opcode) else { throw CodexSocket.Failure.invalidFrame }
            var length = UInt64(b & 127), header = 2
            if length == 126 || length == 127 {
                let count = length == 126 ? 2 : 8
                guard buffer.count - offset >= 2 + count else { break }
                length = 0; header += count
                for byte in buffer[(offset + 2)..<(offset + header)] { length = (length << 8) | UInt64(byte) }
                guard (count == 2 && length >= 126) || (count == 8 && length >= 65536 && length < (1 << 63)) else { throw CodexSocket.Failure.invalidFrame }
            }
            guard length <= Self.maximumBytes else { throw CodexSocket.Failure.oversized }
            guard opcode < 8 || (final && length <= 125) else { throw CodexSocket.Failure.invalidFrame }
            guard buffer.count - offset >= header + Int(length) else { break }
            let payload = Array(buffer[(offset + header)..<(offset + header + Int(length))])
            offset += header + Int(length)
            switch opcode {
            case 0:
                guard var bytes = fragment else { throw CodexSocket.Failure.invalidFrame }
                guard bytes.count <= Self.maximumBytes - payload.count else { throw CodexSocket.Failure.oversized }
                bytes += payload
                if final { try appendText(bytes, to: &events); fragment = nil } else { fragment = bytes }
            case 1:
                guard fragment == nil else { throw CodexSocket.Failure.invalidFrame }
                if final { try appendText(payload, to: &events) } else { fragment = payload }
            case 8:
                guard payload.count != 1 else { throw CodexSocket.Failure.invalidFrame }
                if payload.count >= 2 {
                    let code = UInt16(payload[0]) << 8 | UInt16(payload[1])
                    guard (1000...1014).contains(code) && ![1004, 1005, 1006].contains(code) || (3000...4999).contains(code),
                          String(bytes: payload.dropFirst(2), encoding: .utf8) != nil else { throw CodexSocket.Failure.invalidFrame }
                }
                events.append(.close)
            case 9: events.append(.ping(Data(payload)))
            default: break
            }
        }
        if offset > 0 { buffer.removeFirst(offset) }
        return events
    }
    private func appendText(_ bytes: [UInt8], to events: inout [Event]) throws {
        guard String(bytes: bytes, encoding: .utf8) != nil else { throw CodexSocket.Failure.invalidFrame }
        events.append(.text(Data(bytes)))
    }
}
