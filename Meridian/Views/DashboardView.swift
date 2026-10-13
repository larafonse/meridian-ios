import SwiftUI
import SwiftData
import Charts
import UIKit

struct DashboardView: View {
    @Query(sort: \WeightEntry.recordedAt, order: .reverse) private var entries: [WeightEntry]
    @State private var showingAddSheet = false

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.961, green: 0.941, blue: 0.922, alpha: 1)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(red: 0.961, green: 0.941, blue: 0.922)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Meridian")
                        .font(Font.custom("PlayfairDisplay-Regular", size: 34).weight(.bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))

                    ActivityRingsWidget()

                    WeightChartView(entries: entries)
                        .padding(20)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(red: 0.898, green: 0.898, blue: 0.898), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }

            addButton
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEntrySheet()
        }
    }

    private var addButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color(red: 0.04, green: 0.04, blue: 0.04))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 24)
        .padding(.bottom, 24)
    }
}
