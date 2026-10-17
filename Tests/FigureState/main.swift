import Foundation

for modern in [false, true] {
    let original = RoseEngine(); original.modern = modern; original.tail = 16
    for _ in 0..<23719 { original.step() }
    let state = original.savedFigure()
    let data = try JSONEncoder().encode(state)
    let restored = RoseEngine(); restored.modern = modern; restored.tail = 16
    let decoded = try JSONDecoder().decode([Int].self, from: data)
    precondition(restored.restoreFigure(decoded))
    for n in 0..<1000 {
        original.step(); restored.step()
        precondition(original.savedFigure() == restored.savedFigure())
        if modern {
            for (a,b) in zip(original.modernHistory.last!, restored.modernHistory.last!) {
                precondition(a.x == b.x && a.y == b.y && a.hue == b.hue)
            }
        } else if n >= 40 { precondition(original.pixels == restored.pixels) }
    }
    for (index,bad) in [(0,2),(1,-1),(11,1440),(13,1),(13,999),(16,-1),(16,1),(17,999999),(22,1440),(23,96),(8,Int.max)] {
        var invalid=state; invalid[index]=bad
        let before=restored.savedFigure()
        precondition(!restored.restoreFigure(invalid))
        precondition(before == restored.savedFigure())
    }
    precondition(!restored.restoreFigure([]))
}
print("OK: saved figures resume exact geometry, rotation, colors and simulation; invalid states rejected.")

let longRun = RoseEngine(); longRun.modern = true
var longState = longRun.savedFigure(); longState[1] = 999_999_999_999
precondition(longRun.restoreFigure(longState))
longRun.step()
precondition(longRun.frame == 1_000_000_000_000)
precondition(longRun.modernHistory.last!.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.hue.isFinite })
precondition(RoseEngine().restoreFigure(longRun.savedFigure()))
