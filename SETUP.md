# HealthKit 権限フロー — セットアップ手順

オンボーディングの HealthKit 連携を動かすために、コード以外に必要な Xcode 側の設定をまとめる。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `HealthKitManager.swift` | HealthKit 連携（読み取り専用）。権限リクエストと実績クエリ。 |
| `OnboardingView.swift` | 初回起動の権限取得フロー（事前説明 → OS ダイアログ → 完了）。 |
| `AppRootView.swift` | オンボーディング ⇄ 本体タブの接続。欠損フォールバック + 設定導線の見本。 |
| `Gourmet/LocationProvider.swift` | 位置情報（distanceFilter=100m での移動検知 + ワンショット測位）。 |
| `Gourmet/NetworkMonitor.swift` | オンライン/オフライン監視と復帰検知（NWPathMonitor）。 |
| `Gourmet/PlacesService.swift` | 店舗取得の抽象化。Mock / Google Places 実装。 |
| `Gourmet/GourmetViewModel.swift` | グルメ画面の状態管理（待機・復帰再取得・移動デバウンス）。 |
| `Gourmet/GourmetView.swift` | 周辺グルメ画面（移動バナー / 情報目安注記 / 遅延サムネ）。 |
| `WalkingTrainingApp.swift` | `@main` エントリポイント。 |

## 必須設定（コードだけでは動かない）

### 1. Capability を追加
Xcode → ターゲット → **Signing & Capabilities** → `+ Capability` → **HealthKit** を追加。
（書き込みは使わないので "Clinical Health Records" 等は不要。）

### 2. Info.plist に利用目的を記載
未設定だと `requestAuthorization` でクラッシュする。**審査必須項目**。

```xml
<key>NSHealthShareUsageDescription</key>
<string>歩行練習の実績（歩数・距離・消費カロリー）を読み取り、ダッシュボードに表示するために使用します。</string>
```

> 書き込み権限（`NSHealthUpdateUsageDescription`）は **要求しない** ため記載不要。

#### 位置情報（グルメ機能）
グルメ機能は現在地から半径500mを検索するため、位置情報の利用目的も記載する。

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>現在地周辺で営業中の飲食店を検索するために位置情報を使用します。</string>
```

> 常時測位はしないため `NSLocationAlwaysAndWhenInUseUsageDescription` は不要
> （`distanceFilter=100m` の移動検知 + 手動更新時のワンショット測位のみ）。

### 3. 実機で確認
HealthKit はシミュレータでも一部動くが、データの実体が乏しいため **実機推奨**。
ヘルスケアアプリに手動でサンプルデータ（歩数等）を追加すると挙動確認しやすい。

## 設計上の要点（コードに反映済み）

- **読み取り専用**: `requestAuthorization(toShare: [], read: ...)`。書き込み権限は一切要求しない。
- **拒否を検知できない前提**: read 権限の `authorizationStatus` は信頼できない。
  成否は「実際にクエリして値が取れたか」(`HKStatisticsQuery`) で判定する。
- **0 件 = 拒否と断定しない**: 未計測の可能性があるため、欠損時は「データがありません」と
  フォールバック表示し、エラー扱いしない。
- **再許可はアプリ内不可**: `UIApplication.openSettingsURLString` で設定アプリへ誘導
  （`OnboardingView.openHealthSettings()`）。
- **完了の永続化**: `@AppStorage("didCompleteOnboarding")` で次回起動はオンボーディングをスキップ。

## 実装済み機能（仕様対応）
- 3.1 ダッシュボード／ヘルスケア連携 … `HealthKitManager` + `DashboardView`
- 3.2 周辺グルメ提案 … `Gourmet/`（半径500m / 営業中 / 移動閾値100m / 復帰時自動再取得 / 遅延サムネ / 目安注記）

## レイアウト要件：どの画面サイズでも全画面表示が可能
全ての画面は、端末サイズ（iPhone SE 〜 Pro Max / iPad / 横向き / Split View / Dynamic Type 拡大）
に追従し、余白や見切れなく全画面で表示できること。実装ガイドライン:
- 固定幅・固定高さ（`.frame(width:height:)` の絶対値）を骨格レイアウトに使わない。
  伸縮させる要素は `.frame(maxWidth: .infinity, maxHeight: .infinity)` を用いる。
- 一覧は `List` / `ScrollView`、画面の器は `NavigationStack` を使い、セーフエリアに追従させる。
- 文字は固定 pt ではなく Dynamic Type（`.font(.title3)` 等のテキストスタイル）を基本とする。
- 大画面では `NavigationSplitView` 等で間延びを防ぐ余地を残す（任意）。
- 確認は Xcode Preview の複数デバイス指定、または実機の回転 / Split View で行う。

## 本番化に向けた残作業
- `GooglePlacesService` のレスポンス Codable デコード実装（現状はスケッチ）。
- Core Data 等を再導入する場合は、スキーマのマイグレーション方針を別途検討。
