import SwiftUI
import UIKit
import PiyoCore

/// 保護者向けエリア。子ども向け画面とは見た目もはっきり分ける。
struct ParentAreaView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView {
                ProgressDashboardView()
                    .tabItem {
                        Label("習熟度", systemImage: "chart.bar.fill")
                    }
                    .accessibilityIdentifier(A11yID.parentDashboard)

                ParentSettingsView()
                    .tabItem {
                        Label("設定", systemImage: "gearshape.fill")
                    }
                    .accessibilityIdentifier(A11yID.parentSettings)

                PurchaseView()
                    .tabItem {
                        Label("広告解除", systemImage: "cart.fill")
                    }
                    .accessibilityIdentifier(A11yID.parentPurchase)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(A11yID.parentTabs)
            .navigationTitle("おうちのかた")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                        .accessibilityIdentifier(A11yID.parentClose)
                }
            }
        }
    }
}

/// 習熟度・学習状況。
struct ProgressDashboardView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: ParentDashboardViewModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let model {
                    summaryCards(model)
                    weeklyChart(model)
                    ItemMasterySection(model: model)
                    subjectSection(model)
                    strengthsSection(model)
                    recentSection(model)
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            if model == nil {
                model = ParentDashboardViewModel(environment: environment)
            }
            model?.refresh()
        }
    }

    private func summaryCards(_ model: ParentDashboardViewModel) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(title: "学習した日", value: "\(model.summary.learningDays)日", systemImage: "calendar")
            statCard(title: "学習時間", value: "\(model.totalStudyMinutes)分", systemImage: "clock")
            statCard(title: "といた問題", value: "\(model.summary.totalQuestions)問", systemImage: "list.bullet")
            statCard(title: "正答率", value: model.accuracyText, systemImage: "checkmark.circle")
        }
    }

    private func statCard(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func weeklyChart(_ model: ParentDashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("この 1 週間")
                .font(.headline)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(model.weeklyStats) { stat in
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.tertiarySystemFill))
                                .frame(height: 110)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(PiyoTheme.primary)
                                .frame(
                                    height: max(
                                        4,
                                        110 * CGFloat(stat.questionCount) / CGFloat(model.maximumDailyQuestions)
                                    )
                                )
                        }
                        Text(model.formattedDay(stat.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(stat.questionCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(stat.didStudy ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func subjectSection(_ model: ParentDashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ジャンル別の習熟度")
                .font(.headline)
            if model.summary.subjectStats.isEmpty {
                Text("まだ学習の記録がありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.summary.subjectStats) { stat in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(stat.subject.parentTitle)
                            .font(.subheadline.bold())
                        Spacer()
                        Text(stat.accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.tertiarySystemFill))
                            Capsule()
                                .fill(PiyoTheme.color(for: stat.subject))
                                .frame(width: proxy.size.width * CGFloat(min(max(stat.mastery, 0), 1)))
                        }
                    }
                    .frame(height: 12)
                    Text("\(stat.attempts)問")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func strengthsSection(_ model: ParentDashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("得意・苦手")
                .font(.headline)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("得意", systemImage: "hand.thumbsup.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                    if model.summary.strengths.isEmpty {
                        Text("—").foregroundStyle(.secondary)
                    }
                    ForEach(model.summary.strengths, id: \.self) { subject in
                        Text(subject.parentTitle).font(.subheadline)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label("これから", systemImage: "arrow.up.forward")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    if model.summary.weaknesses.isEmpty {
                        Text("—").foregroundStyle(.secondary)
                    }
                    ForEach(model.summary.weaknesses, id: \.self) { subject in
                        Text(subject.parentTitle).font(.subheadline)
                    }
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func recentSection(_ model: ParentDashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近の学習")
                .font(.headline)
            if model.summary.recentActivities.isEmpty {
                Text("まだ記録がありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.summary.recentActivities) { activity in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.title).font(.subheadline.bold())
                        Text(activity.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(model.formattedDateTime(activity.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }
}
