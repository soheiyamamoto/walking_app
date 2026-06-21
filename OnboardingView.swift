//
//  OnboardingView.swift
//  歩行練習サポートアプリ
//
//  初回起動時の HealthKit 権限取得フロー（プロトタイプ画面①に対応）。
//
//  画面構成:
//   1. 事前説明（なぜ / 何を / 読み取り専用を明示）  → 許可率を上げるための自前画面
//   2. OS 標準ダイアログ（requestAuthorization で iOS が描画。アプリは制御不可）
//   3. 完了 / フォールバック（取得不可でも破綻しない案内 + 設定アプリ導線）
//

import SwiftUI

struct OnboardingView: View {

    @ObservedObject var healthKit: HealthKitManager

    /// オンボーディング完了時に呼ばれる（本体タブへ遷移）。
    var onFinished: () -> Void

    /// 完了済みフラグを永続化（次回起動でスキップ）。
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false

    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)

            // アイコン
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.pink.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "heart.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.pink)
            }

            VStack(spacing: 8) {
                Text("ヘルスケアと連携")
                    .font(.title2.weight(.semibold))
                Text("練習実績を自動で可視化するため、以下のデータを読み取り専用で利用します。書き込み・外部送信は行いません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            // 利用するデータ一覧
            VStack(spacing: 0) {
                permissionRow(
                    icon: "figure.walk",
                    tint: .green,
                    title: "歩数",
                    detail: "日別・週別の集計に使用")
                Divider()
                permissionRow(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    tint: .blue,
                    title: "歩行距離",
                    detail: "目標達成度の算出に使用")
                Divider()
                permissionRow(
                    icon: "flame.fill",
                    tint: .orange,
                    title: "消費カロリー",
                    detail: "運動量の把握に使用")
            }
            .padding(.horizontal, 4)

            Spacer()

            // 主アクション
            VStack(spacing: 10) {
                Button {
                    Task { await requestPermission() }
                } label: {
                    HStack {
                        if isRequesting { ProgressView().tint(.white) }
                        Text(isRequesting ? "確認中…" : "続ける")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
                .disabled(isRequesting || healthKit.isHealthDataUnavailable)

                if healthKit.isHealthDataUnavailable {
                    Text("この端末はヘルスケアに対応していません。手入力で続行できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("次の画面で iOS 標準の許可ダイアログが開きます")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(24)
    }

    // MARK: - 行ビュー

    private func permissionRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 11)
    }

    // MARK: - 権限リクエスト + 結果ハンドリング

    private func requestPermission() async {
        isRequesting = true
        defer { isRequesting = false }

        // 手順 4: OS 標準ダイアログ表示（端末非対応ならスキップ）。
        if !healthKit.isHealthDataUnavailable {
            _ = await healthKit.requestAuthorization()
            // 手順 5: 実際にクエリして当日実績を取得（成否は値の有無で判定）。
            await healthKit.refreshTodaySummary()
        }

        // 拒否されていても先へ進める設計。フォールバックは本体側で表示する。
        didCompleteOnboarding = true
        onFinished()
    }
}

// MARK: - 設定アプリ導線（手順 6: アプリ内で再許可は不可なため）

extension OnboardingView {
    /// 「設定 › プライバシー › ヘルスケア」へ誘導するためのヘルパ。
    /// 本体のダッシュボードでデータ欠損時に使う想定。
    static func openHealthSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    OnboardingView(healthKit: HealthKitManager(), onFinished: {})
}
