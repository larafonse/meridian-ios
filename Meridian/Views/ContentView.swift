import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
                }
            RoutesView()
                .tabItem {
                    Label("Routes", systemImage: "map")
                }
            LogView()
                .tabItem {
                    Label("Log", systemImage: "list.bullet")
                }
        }
        .tint(Color(red: 0.04, green: 0.04, blue: 0.04))
    }
}
