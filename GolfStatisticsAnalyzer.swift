import Foundation

struct GolfStatisticsAnalyzer {

    struct Summary {
        var totalRounds = 0
        var averageScore = 0.0
        var bestScore = 0
        var averagePutts = 0.0
        var averageDriverDistance = 0.0
        var fairwayAccuracy = 0.0
        var girAccuracy = 0.0
        var handicapIndex: Double? = nil
    }

    /// WHS(USGA 2020~) 방식: 최근 20라운드 중 좋은 차이값 평균 (3라운드 미만이면 nil)
    static func handicapIndex(from records: [RoundRecord]) -> Double? {
        let recent = records.filter { !$0.isArchived }
            .sorted { $0.date > $1.date }
            .prefix(20)
        guard recent.count >= 3 else { return nil }

        let diffs = recent
            .map { (Double($0.totalScore) - $0.courseRating) * 113.0 / $0.slopeRating }
            .sorted()

        let (use, adjust) = rule(for: diffs.count)
        let avg = diffs.prefix(use).reduce(0, +) / Double(use)
        return max(0, ((avg + adjust) * 10).rounded() / 10)
    }

    private static func rule(for count: Int) -> (Int, Double) {
        switch count {
        case 3: return (1, -2.0)
        case 4: return (1, -1.0)
        case 5: return (1, 0)
        case 6: return (2, -1.0)
        case 7, 8: return (2, 0)
        case 9...11: return (3, 0)
        case 12...14: return (4, 0)
        case 15, 16: return (5, 0)
        case 17, 18: return (6, 0)
        case 19: return (7, 0)
        default: return (8, 0)
        }
    }

    static func summary(from records: [RoundRecord]) -> Summary {
        let valid = records.filter { !$0.isArchived }
        guard !valid.isEmpty else { return Summary() }
        let n = Double(valid.count)

        let fwHit = Double(valid.map(\.fairwaysHit).reduce(0, +))
        let fwTotal = Double(valid.map(\.totalFairways).reduce(0, +))
        let girSum = Double(valid.map(\.greensInRegulation).reduce(0, +))
        let drivers = valid.map(\.driverDistance).filter { $0 > 0 }

        return Summary(
            totalRounds: valid.count,
            averageScore: Double(valid.map(\.totalScore).reduce(0, +)) / n,
            bestScore: valid.map(\.totalScore).min() ?? 0,
            averagePutts: Double(valid.map(\.totalPutts).reduce(0, +)) / n,
            averageDriverDistance: drivers.isEmpty ? 0 : drivers.reduce(0, +) / Double(drivers.count),
            fairwayAccuracy: fwTotal > 0 ? fwHit / fwTotal * 100 : 0,
            girAccuracy: girSum / (n * 18) * 100,
            handicapIndex: handicapIndex(from: valid)
        )
    }
}
