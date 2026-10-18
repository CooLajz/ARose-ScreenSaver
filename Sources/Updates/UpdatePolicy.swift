import Foundation

enum ARoseUpdatePolicy {
    static func shouldInstallSaver(embeddedBuild: String?, installedBuild: String?) -> Bool {
        guard let text = embeddedBuild, let embedded = UInt64(text), embedded > 0 else { return false }
        guard let installedBuild else { return true }
        guard let installed = UInt64(installedBuild) else { return false }
        return embedded > installed
    }
    // Clock rollback must not prevent checks indefinitely. Failed attempts also
    // count, so an offline machine does not contact GitHub every hour.
    static func due(last: Double, now: Double) -> Bool {
        last <= 0 || now < last || now - last >= 7 * 24 * 60 * 60
    }
}
