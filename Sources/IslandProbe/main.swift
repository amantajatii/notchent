import Foundation
import IslandCore
let args = Array(CommandLine.arguments.dropFirst())
let scenario = args.first ?? "inventory"
let observations: [CapabilityObservation]
switch scenario {
case "inventory": observations = AgentProbe().inventory()
case "agent":
    if args.count == 3, args[1] == "--pid", let pid = Int32(args[2]), pid > 0 {
        observations = AgentProbe().inspect(pid: pid)
    } else {
        observations = [CapabilityObservation(capability: "agent", outcome: .unavailable, evidence: "Select exactly one controlled session with agent --pid <positive PID>. No selection made.")]
    }
case "panel": PanelProbe.run()
case "drag", "spotify":
    observations = [CapabilityObservation(capability: scenario, outcome: .unsupported, evidence: "Scenario not implemented in Task 1.")]
default:
    observations = [CapabilityObservation(capability: "scenario", outcome: .unsupported, evidence: "Unknown scenario. Available names: inventory, agent, panel, drag, spotify.")]
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
do { let data = try encoder.encode(observations); print(String(decoding: data, as: UTF8.self)) }
catch { fputs("Could not encode probe observations.\n", stderr); exit(1) }
