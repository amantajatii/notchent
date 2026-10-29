import Foundation
import Testing
@testable import IslandMac

struct CodexSocketTests {
    private let key = "dGhlIHNhbXBsZSBub25jZQ=="
    private let upgrade = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: keep-alive, Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n"
    private func frame(_ bytes: [UInt8], opcode: UInt8 = 1, final: Bool = true) -> Data {
        let a = (final ? 128 : 0) | opcode
        if bytes.count < 126 { return Data([a, UInt8(bytes.count)] + bytes) }
        return Data([a, 126, UInt8(bytes.count >> 8), UInt8(bytes.count & 255)] + bytes)
    }
    @Test func handshakeChecksChallengeAndUpgradeHeaders() throws {
        try CodexWebSocketCodec.validateHandshake(Data(upgrade.utf8), key: key)
        for bad in [upgrade.replacingOccurrences(of: "101", with: "200"), upgrade.replacingOccurrences(of: "Upgrade: websocket", with: "Upgrade: h2"), upgrade.replacingOccurrences(of: "keep-alive, Upgrade", with: "keep-alive"), upgrade.replacingOccurrences(of: "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", with: "wrong"), upgrade.replacingOccurrences(of: "\r\n\r\n", with: "\r\nSec-WebSocket-Extensions: permessage-deflate\r\n\r\n")] {
            #expect(throws: CodexSocket.Failure.invalidHandshake) { try CodexWebSocketCodec.validateHandshake(Data(bad.utf8), key: key) }
        }
    }
    @Test func splitFramesPreserveFragmentedUTF8AndInterleavedPing() throws {
        var codec = CodexWebSocketCodec()
        let first = frame([0x7b, 0x22, 0xc3], final: false)
        #expect(try codec.append(first.prefix(1)).isEmpty)
        #expect(try codec.append(first.dropFirst()).isEmpty)
        let ping = frame([1, 2], opcode: 9)
        #expect(try codec.append(ping) == [.ping(Data([1, 2]))])
        let last = frame([0xa9, 0x22, 0x7d], opcode: 0)
        #expect(try codec.append(last) == [.text(Data("{\"é\"}".utf8))])
        #expect(try codec.append(frame(Array("{}".utf8)) + frame(Array("[]".utf8))) == [.text(Data("{}".utf8)), .text(Data("[]".utf8))])
    }
    @Test func protocolViolationsFailClosedBeforeAllocatingPayloads() {
        let invalid: [[UInt8]] = [
            [0x81, 0x80], // Server frames may not be masked.
            [0xc1, 0], // No extensions were negotiated.
            [0x82, 0], // Binary input is not JSON text.
            [0x80, 0], // Continuation without a text fragment.
            [0x09, 0], // Fragmented ping.
            [0x89, 126, 0, 126], // Oversized control frame.
            [0x81, 126, 0, 1], // Noncanonical length.
            [0x88, 1, 0], // Invalid close body.
            [0x81, 1, 0xff], // Invalid UTF-8.
            [0x88, 2, 3, 237] // Reserved close code 1005.
        ]
        for bytes in invalid {
            var codec = CodexWebSocketCodec()
            #expect(throws: CodexSocket.Failure.invalidFrame) { try codec.append(Data(bytes)) }
        }
        var codec = CodexWebSocketCodec()
        #expect(throws: CodexSocket.Failure.oversized) { try codec.append(Data([0x81, 127, 0, 0, 0, 0, 0, 64, 0, 1])) }
    }
    @Test func clientFramesAreMaskedWithCorrectLengthAtAllBoundaries() {
        for count in [0, 1, 125, 126, 65535, 65536] {
            let body = Data(repeating: 0x42, count: count)
            let bytes = Array(CodexWebSocketCodec.clientFrame(body))
            #expect(bytes[0] == 0x81)
            #expect(bytes[1] & 128 == 128)
            let lengthBytes = bytes[1] & 127 == 126 ? 2 : (bytes[1] & 127 == 127 ? 8 : 0)
            var encodedCount = lengthBytes == 0 ? UInt64(bytes[1] & 127) : 0
            for byte in bytes[2..<(2 + lengthBytes)] { encodedCount = encodedCount << 8 | UInt64(byte) }
            #expect(encodedCount == count)
            let mask = Array(bytes[(2 + lengthBytes)..<(6 + lengthBytes)])
            let decoded = bytes.dropFirst(6 + lengthBytes).enumerated().map { $0.element ^ mask[$0.offset % 4] }
            #expect(Data(decoded) == body)
        }
    }
}
