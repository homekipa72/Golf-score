import Foundation
import SwiftData

enum DataSource: String, Codable, CaseIterable {
    case manual = "직접 입력"
    case csv = "CSV"
}

@Model
final class RoundRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var courseName: String = ""
    var totalScore: Int = 0
    var totalPutts: Int = 0
    var fairwaysHit: Int = 0
    var totalFairways: Int = 14
    var greensInRegulation: Int = 0
    var driverDistance: Double = 0      // 0 = 미입력
    var courseRating: Double = 72.0
    var slopeRating: Double = 113.0
    var dataSource: DataSource = DataSource.manual
    @Attribute(.externalStorage) var scorecardImageData: Data?
    var isArchived: Bool = false        // 삭제 표시 (휴지통 개념)
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \HoleScore.round)
    var holes: [HoleScore]? = []

    init(date: Date, courseName: String, totalScore: Int, totalPutts: Int,
         fairwaysHit: Int, totalFairways: Int, greensInRegulation: Int,
         driverDistance: Double = 0, courseRating: Double = 72.0, slopeRating: Double = 113.0,
         dataSource: DataSource = .manual, scorecardImageData: Data? = nil) {
        self.date = date
        self.courseName = courseName
        self.totalScore = totalScore
        self.totalPutts = totalPutts
        self.fairwaysHit = fairwaysHit
        self.totalFairways = totalFairways
        self.greensInRegulation = greensInRegulation
        self.driverDistance = driverDistance
        self.courseRating = courseRating
        self.slopeRating = slopeRating
        self.dataSource = dataSource
        self.scorecardImageData = scorecardImageData
    }
}

@Model
final class HoleScore {
    var holeNumber: Int = 1
    var par: Int = 4
    var strokes: Int = 4
    var putts: Int = 2
    var fairwayHit: Bool = false
    var greenInRegulation: Bool = false
    var round: RoundRecord?

    init(holeNumber: Int, par: Int, strokes: Int, putts: Int, fairwayHit: Bool, greenInRegulation: Bool) {
        self.holeNumber = holeNumber
        self.par = par
        self.strokes = strokes
        self.putts = putts
        self.fairwayHit = fairwayHit
        self.greenInRegulation = greenInRegulation
    }
}

@Model
final class WatchActivity {
    var startTime: Date = Date()
    var sport: String = ""
    var durationSeconds: Double = 0
    var distanceMeters: Double = 0
    var calories: Int = 0
    var avgHeartRate: Int = 0
    var maxHeartRate: Int = 0
    @Attribute(.externalStorage) var routeData: Data?
    var createdAt: Date = Date()

    init(startTime: Date, sport: String, durationSeconds: Double, distanceMeters: Double,
         calories: Int, avgHeartRate: Int, maxHeartRate: Int, routeData: Data?) {
        self.startTime = startTime
        self.sport = sport
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.calories = calories
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.routeData = routeData
    }

    var route: [RoutePoint] {
        guard let routeData else { return [] }
        return (try? JSONDecoder().decode([RoutePoint].self, from: routeData)) ?? []
    }
}
