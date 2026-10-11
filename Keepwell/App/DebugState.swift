import Foundation

#if DEBUG
/// Screenshot-proof helper (DEBUG only): records what the app is showing so the Simulator job can
/// verify each capture is authorized and populated. Written to Documents/kw-state.json.
@MainActor
enum KWDebugState {
    private static var values: [String: Any] = [:]

    static var isActive: Bool { UserDefaults.standard.string(forKey: "KWScreen") != nil }

    static func set(_ pairs: [String: Any]) {
        guard isActive else { return }
        for (k, v) in pairs { values[k] = v }
        flush()
    }

    private static func flush() {
        guard JSONSerialization.isValidJSONObject(values),
              let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys, .prettyPrinted]) else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? data.write(to: dir.appendingPathComponent("kw-state.json"), options: .atomic)
    }
}
#endif
