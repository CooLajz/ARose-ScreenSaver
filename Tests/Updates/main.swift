import Foundation
func check(_ condition: Bool) { precondition(condition) }
check(ARoseUpdatePolicy.due(last: 0, now: 1))
check(!ARoseUpdatePolicy.due(last: 100, now: 100))
check(!ARoseUpdatePolicy.due(last: 100, now: 604899))
check(ARoseUpdatePolicy.due(last: 100, now: 604900))
check(ARoseUpdatePolicy.due(last: 100, now: 99))
print("Weekly update policy passed (Swift)")

check(ARoseUpdatePolicy.shouldInstallSaver(embeddedBuild: "5", installedBuild: "4"))
check(ARoseUpdatePolicy.shouldInstallSaver(embeddedBuild: "5", installedBuild: nil))
check(!ARoseUpdatePolicy.shouldInstallSaver(embeddedBuild: "4", installedBuild: "5"))
check(!ARoseUpdatePolicy.shouldInstallSaver(embeddedBuild: "4", installedBuild: "4"))
check(!ARoseUpdatePolicy.shouldInstallSaver(embeddedBuild: nil, installedBuild: "4"))
check(!ARoseUpdatePolicy.shouldInstallSaver(embeddedBuild: "5", installedBuild: "invalid"))
print("Managed saver synchronization never downgrades a newer standalone saver")
