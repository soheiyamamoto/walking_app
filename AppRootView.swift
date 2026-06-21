//
//  AppRootView.swift
//  歩行練習サポートアプリ
//
//  オンボーディング → 本体タブ の接続点。
//  ダッシュボードでの「データ欠損フォールバック + 設定アプリ導線」（手順 6）の見本を含む。
//

import SwiftUI

struct AppRootView: View {
    @StateObject private var healthKit = HealthKitManager()
    // グルメ機能の位置 / ネットワーク監視はアプリで 1 つ共有する。
    @StateObject private var location = LocationProvider()
    @StateObject private var network = NetworkMonitor()
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false

    var body: some View {
        Group {
            if didCompleteOnboarding {
                MainTabView(healthKit: healthKit, location: location, network: network)
            } else {
                OnboardingView(healthKit: healthKit) {
                    // onFinished: AppStorage 更新は OnboardingView 内で実施済み。
                }
            }
        }
        .task {
            // 2 回目以降の起動: 既に許可済みなら値の再取得のみ。
            if didCompleteOnboarding {
                await healthKit.refreshTodaySummary()
            }
        }
    }
}

// MARK: - 本体（3 タブ。グルメ / 記録は別途実装する想定のためここでは枠のみ）

struct MainTabView: View {
    @ObservedObject var healthKit: HealthKitManager
    @ObservedObject var location: LocationProvider
    @ObservedObject var network: NetworkMonitor

    var body: some View {
        TabView {
            DashboardView(healthKit: healthKit)
                .tabItem { Label("ダッシュボード", systemImage: "chart.bar.fill") }

            GourmetView(location: location, network: network)
                .tabItem { Label("グルメ", systemImage: "fork.knife") }
        }
    }
}

// MARK: - ダッシュボード（HealthKit 値の表示 + 欠損フォールバック）

struct DashboardView: View {
    @ObservedObject var healthKit: HealthKitManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 3 指標カード（取れない値は "—" 表示）
                    HStack(spacing: 8) {
                        statCard(value: healthKit.todaySummary.stepsText, unit: "歩")
                        statCard(value: healthKit.todaySummary.distanceText, unit: "km")
                        statCard(value: healthKit.todaySummary.kcalText, unit: "kcal")
                    }

                    // 全指標が取れない場合のみフォールバック表示。
                    // 「拒否」と断定せず、設定アプリへの導線を出す（手順 6）。
                    if healthKit.todaySummary.isAllMissing {
                        VStack(spacing: 10) {
                            Image(systemName: "heart.slash")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Text("ヘルスケアのデータがありません")
                                .font(.subheadline.weight(.medium))
                            Text("まだ計測されていないか、アクセスが許可されていない可能性があります。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("設定で許可を確認") {
                                OnboardingView.openHealthSettings()
                            }
                            .font(.subheadline)
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding()
            }
            .navigationTitle("今日の実績")
            .refreshable { await healthKit.refreshTodaySummary() }
            .task { await healthKit.refreshTodaySummary() }
        }
    }

    private func statCard(value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.semibold))
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    AppRootView()
}
