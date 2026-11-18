import SwiftUI
import SwiftData
import MapKit
import Charts

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds)
    return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
}

private func thin<T>(_ a: [T], max limit: Int) -> [T] {
    guard a.count > limit else { return a }
    let step = Int((Double(a.count) / Double(limit)).rounded(.up))
    return stride(from: 0, to: a.count, by: step).map { a[$0] }
}

struct WatchActivityListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WatchActivity.startTime, order: .reverse) private var activities: [WatchActivity]

    var body: some View {
        NavigationStack {
            List {
                if activities.isEmpty {
                    ContentUnavailableView("워치 활동 없음", systemImage: "applewatch",
                        description: Text("데이터 관리 탭에서 FIT 파일을 가져오세요."))
                }
                ForEach(activities) { a in
                    NavigationLink(destination: WatchActivityDetailView(activity: a)) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(a.sport).bold()
                                Spacer()
                                Text(a.startTime.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("\(formatDuration(a.durationSeconds)) · \(String(format: "%.1f", a.distanceMeters / 1000))km · \(a.calories)kcal")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { for i in $0 { modelContext.delete(activities[i]) } }
            }
            .navigationTitle("워치 활동")
        }
    }
}

struct WatchActivityDetailView: View {
    let activity: WatchActivity
    @State private var points: [RoutePoint] = []

    private var coords: [CLLocationCoordinate2D] {
        thin(points.compactMap { p -> CLLocationCoordinate2D? in
            guard let la = p.lat, let lo = p.lon else { return nil }
            return CLLocationCoordinate2D(latitude: la, longitude: lo)
        }, max: 1000)
    }

    private var hrSeries: [(x: Double, y: Int)] {
        guard let t0 = points.first?.t else { return [] }
        return thin(points.compactMap { p -> (x: Double, y: Int)? in
            guard let h = p.hr else { return nil }
            return (x: (p.t - t0) / 60.0, y: h)
        }, max: 500)
    }

    private var mapRect: MKMapRect {
        coords.reduce(MKMapRect.null) {
            $0.union(MKMapRect(origin: MKMapPoint($1), size: MKMapSize(width: 0, height: 0)))
        }.insetBy(dx: -3000, dy: -3000)
    }

    var body: some View {
        List {
            Section("요약") {
                LabeledContent("종목", value: activity.sport)
                LabeledContent("시작", value: activity.startTime.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("시간", value: formatDuration(activity.durationSeconds))
                LabeledContent("거리", value: String(format: "%.2f km", activity.distanceMeters / 1000))
                LabeledContent("칼로리", value: "\(activity.calories) kcal")
                LabeledContent("심박 (평균/최대)", value: "\(activity.avgHeartRate) / \(activity.maxHeartRate)")
            }
            if coords.count > 1 {
                Section("이동 경로") {
                    Map(initialPosition: .rect(mapRect)) {
                        MapPolyline(coordinates: coords).stroke(.green, lineWidth: 3)
                    }
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
                }
            }
            if hrSeries.count > 1 {
                Section("심박수 (분)") {
                    Chart(hrSeries, id: \.x) { item in
                        LineMark(x: .value("분", item.x), y: .value("심박", item.y))
                            .foregroundStyle(.red)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                }
            }
        }
        .navigationTitle("활동 상세")
        .navigationBarTitleDisplayMode(.inline)
        .task { points = activity.route }
    }
}
