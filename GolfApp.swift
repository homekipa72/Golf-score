import SwiftUI
import SwiftData

@main
struct GolfManagerApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                GolfDashboardView()
                    .tabItem { Label("라운드 기록", systemImage: "figure.golf") }
                NavigationStack { GolfStatisticsView() }
                    .tabItem { Label("종합 분석", systemImage: "chart.bar.fill") }
                WatchActivityListView()
                    .tabItem { Label("워치 활동", systemImage: "applewatch") }
                NavigationStack { DataManagementView() }
                    .tabItem { Label("데이터 관리", systemImage: "gearshape.fill") }
            }
            .tint(.green)
        }
        .modelContainer(for: [RoundRecord.self, HoleScore.self, WatchActivity.self])
    }
}
