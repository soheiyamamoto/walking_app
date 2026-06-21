//
//  HealthKitManager.swift
//  歩行練習サポートアプリ
//
//  HealthKit 連携（読み取り専用）を担うマネージャ。
//
//  設計方針:
//   - 書き込み権限は要求しない（toShare: []）。歩数 / 歩行距離 / 消費カロリーの read のみ。
//   - iOS の仕様上、read 権限の authorizationStatus はプライバシー保護のため
//     「拒否されたか未許可か」を正確に返さない。よって権限の成否は
//     authorizationStatus ではなく「実際にクエリして値が取れたか」で判定する。
//   - 一度でも 0 件 = 拒否、とは断定しない（未計測の可能性があるため）。
//     データが取れなければ「データがありません」とフォールバック表示する。
//

import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {

    // MARK: - 公開状態（View からバインドする）

    /// オンボーディングの権限リクエストが一度完了したか（成否は問わない）
    @Published var hasRequestedAuthorization: Bool = false

    /// 直近に取得できた当日の実績。取れなかった指標は nil（= 表示は「—」）。
    @Published var todaySummary: DailySummary = .empty

    /// 端末が HealthKit 非対応（iPad 等）の場合 true
    let isHealthDataUnavailable: Bool

    // MARK: - 内部

    private let store = HKHealthStore()

    /// 読み取りを要求する型。ここに無いものは一切要求しない。
    private let readTypes: Set<HKObjectType> = {
        var set = Set<HKObjectType>()
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            set.insert(steps)
        }
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            set.insert(distance)
        }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            set.insert(energy)
        }
        return set
    }()

    init() {
        isHealthDataUnavailable = !HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - 権限リクエスト（オンボーディング手順 4）

    /// OS 標準の許可ダイアログを表示する。
    /// 呼び出しは初回オンボーディング時の 1 回でよい（再呼び出ししてもダイアログは再表示されない）。
    /// - Note: ここでの戻り値は「ダイアログ操作が完了したか」であって「許可されたか」ではない。
    func requestAuthorization() async -> Bool {
        guard !isHealthDataUnavailable else { return false }
        do {
            // toShare: [] → 書き込み権限は一切要求しない（読み取り専用）。
            try await store.requestAuthorization(toShare: [], read: readTypes)
            hasRequestedAuthorization = true
            return true
        } catch {
            // ダイアログ提示自体に失敗（端末状態など）。呼び出し側でリトライ導線を出す。
            hasRequestedAuthorization = false
            return false
        }
    }

    // MARK: - 実績取得（オンボーディング手順 5 / ダッシュボード用）

    /// 当日 0:00 〜 現在 の合計を各指標について取得し todaySummary に反映する。
    /// 取れなかった指標は nil のまま（拒否 or 未計測。区別せずフォールバック表示する方針）。
    func refreshTodaySummary() async {
        guard !isHealthDataUnavailable else {
            todaySummary = .empty
            return
        }

        async let steps = sumQuantityToday(
            identifier: .stepCount, unit: .count())
        async let distanceMeters = sumQuantityToday(
            identifier: .distanceWalkingRunning, unit: .meter())
        async let kcal = sumQuantityToday(
            identifier: .activeEnergyBurned, unit: .kilocalorie())

        let stepsValue = await steps
        let distanceValue = await distanceMeters
        let kcalValue = await kcal

        todaySummary = DailySummary(
            steps: stepsValue.map { Int($0.rounded()) },
            distanceKm: distanceValue.map { $0 / 1000.0 },
            activeKcal: kcalValue.map { Int($0.rounded()) }
        )
    }

    /// 指定指標の当日合計を取得。権限が無い / データが無い場合は nil を返す。
    private func sumQuantityToday(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                // エラー / 権限なし / データなし は一律 nil（呼び出し側でフォールバック）。
                let value = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}

// MARK: - 表示用モデル

/// 当日実績のスナップショット。各値は nil 許容（取得不可 = 「—」表示）。
struct DailySummary {
    let steps: Int?
    let distanceKm: Double?
    let activeKcal: Int?

    static let empty = DailySummary(steps: nil, distanceKm: nil, activeKcal: nil)

    /// 3 指標すべてが取得できなかったか（= 権限拒否 or 完全未計測の可能性）
    var isAllMissing: Bool {
        steps == nil && distanceKm == nil && activeKcal == nil
    }

    var stepsText: String { steps.map { "\($0.formatted())" } ?? "—" }
    var distanceText: String { distanceKm.map { String(format: "%.1f", $0) } ?? "—" }
    var kcalText: String { activeKcal.map { "\($0)" } ?? "—" }
}
