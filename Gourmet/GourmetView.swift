//
//  GourmetView.swift
//  歩行練習サポートアプリ
//
//  周辺グルメ画面（プロトタイプ画面②グルメタブに対応）。
//
//  反映している論点:
//   - 移動閾値 100m + 手動更新デバウンス → 移動時は更新バナーのみ表示、取得はタップで 1 回。
//   - 「情報は目安」注記 → リスト下に常設の免責表示。
//   - オフライン待機 / 復帰時の自動再取得 → ViewModel が制御。
//   - 通信量対策 → サムネは AsyncImage で遅延読み込み（低解像度 URL 前提）。
//

import SwiftUI

struct GourmetView: View {
    @StateObject private var vm: GourmetViewModel

    init(location: LocationProvider, network: NetworkMonitor,
         places: PlacesService = MockPlacesService()) {
        _vm = StateObject(wrappedValue:
            GourmetViewModel(location: location, network: network, places: places))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("周辺グルメ")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { networkBadge }
                }
        }
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
    }

    // MARK: - 状態ごとの本体

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .offline:
            standby(icon: "wifi.slash", title: "オフラインのため待機中",
                    message: "電波復帰時に現在地で自動再取得します")
        case .locationDenied:
            standby(icon: "location.slash", title: "位置情報が許可されていません",
                    message: "設定アプリで位置情報の利用を許可してください") {
                Button("設定を開く") { OnboardingView.openHealthSettings() }
                    .buttonStyle(.bordered)
            }
        case .loading, .idle:
            ProgressView("検索中…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            standby(icon: "fork.knife", title: "営業中の店舗が見つかりません",
                    message: "半径500m以内に該当する店舗がありませんでした") {
                Button("現在地で再検索") { vm.refreshTapped() }.buttonStyle(.bordered)
            }
        case .failed:
            standby(icon: "exclamationmark.triangle", title: "取得に失敗しました",
                    message: "通信状況をご確認のうえ、もう一度お試しください") {
                Button("再試行") { vm.refreshTapped() }.buttonStyle(.bordered)
            }
        case .loaded(let restaurants):
            list(restaurants)
        }
    }

    // MARK: - リスト表示

    private func list(_ restaurants: [Restaurant]) -> some View {
        List {
            // 半径・営業中の説明
            Section {
                ForEach(restaurants) { RestaurantRow(restaurant: $0) }
            } header: {
                Text("半径500m以内・営業中")
            } footer: {
                disclaimerNote   // 「情報は目安」注記
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .top) { updateBanner }   // 移動検知バナー（必要時のみ）
        .safeAreaInset(edge: .bottom) { manualRefreshBar }
    }

    // MARK: - 100m 移動バナー（自動取得せず、タップで 1 回更新）

    @ViewBuilder
    private var updateBanner: some View {
        if vm.showUpdateBanner {
            HStack(spacing: 10) {
                Image(systemName: "location.fill.viewfinder")
                Text("100m以上移動しました").font(.subheadline)
                Spacer()
                Button("この場所で更新") { vm.refreshTapped() }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.blue.opacity(0.12))
            .foregroundStyle(Color.blue)
        }
    }

    // MARK: - 「情報は目安」注記（論点 2）

    private var disclaimerNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
            Text("営業時間は提供元データに基づく目安です。実際の営業状況と異なる場合があります。")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private var manualRefreshBar: some View {
        Button {
            vm.refreshTapped()
        } label: {
            Label("現在地で手動更新", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .padding()
        .background(.bar)
    }

    // MARK: - 補助ビュー

    private var networkBadge: some View {
        Label(vm.network.isOnline ? "オンライン" : "オフライン",
              systemImage: vm.network.isOnline ? "wifi" : "wifi.slash")
            .font(.caption)
            .foregroundStyle(vm.network.isOnline ? Color.green : Color.red)
    }

    private func standby(icon: String, title: String, message: String,
                         @ViewBuilder action: () -> some View = { EmptyView() }) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 32)).foregroundStyle(.tertiary)
            Text(title).font(.subheadline.weight(.medium))
            Text(message).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            action()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 店舗行（サムネは遅延読み込み）

struct RestaurantRow: View {
    let restaurant: Restaurant

    var body: some View {
        HStack(spacing: 12) {
            // 通信量対策: 低解像度サムネを AsyncImage で遅延取得。
            // 読み込み前後ともプレースホルダを出し、テキストは先に表示される。
            AsyncImage(url: restaurant.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Color(.secondarySystemBackground)
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(restaurant.name).font(.subheadline.weight(.medium))
                Text([restaurant.distanceText,
                      restaurant.isOpenNow ? "営業中" : "",
                      restaurant.closingText]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ・ "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    GourmetView(location: LocationProvider(), network: NetworkMonitor())
}
