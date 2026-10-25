import Foundation
// The String Catalog is the only authored translation source. CLT has no xcstringstool.
let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Usage: export-localizations.swift catalog output-directory") }
let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [String: Any]
let strings = catalog["strings"] as! [String: [String: Any]]
for language in ["en", "id"] {
    var entries: [String] = []
    for key in strings.keys.sorted() {
        let localization = strings[key]!["localizations"] as! [String: [String: Any]]
        let unit = localization[language]!["stringUnit"] as! [String: String]
        func quote(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
        }
        entries.append("\(quote(key)) = \(quote(unit["value"]!));")
    }
    let directory = URL(fileURLWithPath: args[2]).appendingPathComponent("\(language).lproj")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try (entries.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
}
