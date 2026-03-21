# iTerm2 メニュー日本語化 — 現状分析と対応方針

---

## 目次

1. [現行ローカライズ仕様](#1-現行ローカライズ仕様)
2. [メニュー定義の構成](#2-メニュー定義の構成)
3. [ハードコード状態の調査結果](#3-ハードコード状態の調査結果)
4. [日本語化の対応方式](#4-日本語化の対応方式)
5. [対象文字列の全量見積もり](#5-対象文字列の全量見積もり)
6. [優先度別の作業計画](#6-優先度別の作業計画)

---

## 1. 現行ローカライズ仕様

### 1.1 プロジェクト設定

| 項目 | 値 |
|------|-----|
| `CFBundleDevelopmentRegion` | `en`（英語） |
| `LOCALIZATION_PREFERS_STRING_CATALOGS` | `YES`（String Catalog 対応準備済み） |
| 日本語バンドル（`ja.lproj`） | **存在しない** |
| 対応言語 | 英語のみ |

### 1.2 既存の .strings ファイル

`.strings` ファイルは `Interfaces/` にあるが、**すべて英語→英語のアイデンティティマッピング**（翻訳なし）。

| ファイル | パス | エントリ数 | 用途 |
|---------|------|-----------|------|
| `MainMenu.strings` | `Interfaces/MainMenu.strings` | 59 | メインメニューバーの項目 |
| `PreferencePanel.strings` | `Interfaces/PreferencePanel.strings` | 158 | 設定画面のラベル |
| `AddressBook.strings` | `Interfaces/AddressBook.strings` | 92 | プロファイル管理画面 |
| `iTerm.strings` | `Interfaces/iTerm.strings` | 124 | コンテキストメニュー、ツールバー、アラート |
| `configPanel.strings` | `Interfaces/configPanel.strings` | 19 | 設定パネル |
| `PseudoTerminal.strings` | `Interfaces/PseudoTerminal.strings` | 1 | ターミナルウィンドウ |
| **合計** | | **453** | |

#### MainMenu.strings の現状例

```
/* 現在: 英語→英語（翻訳されていない） */
"Copy" = "Copy";
"Edit" = "Edit";
"New Tab" = "New Tab";
"New Window" = "New Window";
"Paste" = "Paste";
"Preferences..." = "Settings...";  /* 唯一 value が異なる（リネーム） */
"Quit iTerm" = "Quit iTerm";
"Shell" = "Shell";
"View" = "View";
"Window" = "Window";
```

### 1.3 XIB ファイル

30 以上の `.xib` ファイルが `Interfaces/` に存在。すべて **Base ローカライズ**（英語直書き）。

| 主要 XIB | サイズ | 内容 |
|----------|--------|------|
| `MainMenu.xib` | 161 KB | メインメニューバー全体 |
| `PreferencePanel.xib` | 1.1 MB | 設定画面（最大） |
| `ProfilesWindow.xib` | 12 KB | プロファイルウィンドウ |
| `TmuxDashboard.xib` | 28 KB | tmux ダッシュボード |
| その他 25+ | — | 各種ダイアログ・パネル |

### 1.4 NSLocalizedString の使用状況

**使用マクロ**: `NSLocalizedStringFromTableInBundle`（テーブル名: `@"iTerm"`）

```objc
// 使用パターン
NSLocalizedStringFromTableInBundle(@"Copy",
                                   @"iTerm",
                                   [NSBundle bundleForClass:[self class]],
                                   @"Context menu")
```

| 指標 | 値 |
|------|-----|
| 使用ファイル数 | 13 (.m ファイル) |
| 使用箇所数 | 46 箇所 |
| 全ソースファイル数 | 1,344（.m: 807, .swift: 537） |
| ローカライズマクロ使用率 | **約 1%** |

**結論**: ソースコードの 99% は `NSLocalizedString` を使わず、英語文字列を直書きしている。

### 1.5 ローカライズツール

`tools/applyLocalization.sh` が存在し、`nibtool` で `.strings` → `.nib` に翻訳を適用する仕組みがある。

```bash
# 想定ディレクトリ構造
English.lproj/      # マスター NIB
ja.lproj/           # 翻訳済み .strings → nibtool で NIB 生成
```

ただし現在 `English.lproj` は存在せず、このスクリプトは**未使用状態**。

---

## 2. メニュー定義の構成

### 2.1 メインメニューバー（MainMenu.xib）

XIB で定義されているトップレベルメニュー:

| メニュー | 主な項目 |
|---------|---------|
| **iTerm2**（Apple メニュー） | About, Settings, Services, Hide, Quit |
| **Shell** | New Window/Tab, Split, Close, Broadcasting, tmux, SSH |
| **Edit** | Undo, Cut, Copy, Paste, Find, AI commands |
| **View** | Toolbelt, Transparency, Zoom, Timestamps, Instant Replay |
| **Session** | Edit Session, History, Paste History, Reset, Bury |
| **Profiles** | プロファイル選択（動的生成） |
| **Window** | Arrangements, Tab管理, Split Pane, Window Styles |
| **Help** | iTerm2 Help, Licenses, GPU Info |

### 2.2 プログラム的に生成されるメニュー

XIB の静的定義に加え、多数のメニュー項目がランタイムで動的に生成される。

#### iTermApplicationDelegate.m（主要メニュービルダー）

```objc
// ハードコードされたメニュー文字列の例
@"New Window (Default Profile)"
@"New Window…"
@"New Tab…"
@"Clear All"
@"Undo Close Session"
@"New Tab At End" / @"New Tab Next to Current Tab"
@"Downloads" / @"Uploads"
@"Toggle Key Recording"
@"Replay Recorded Keys"
@"Settings"
@"Bring All Windows to Front"
@"Check For Updates"
@"Quit iTerm2"
```

#### PseudoTerminal.m（タブ右クリックメニュー）

```objc
@"New Tab to the Right"
@"Close Tab"
@"Duplicate Tab"
@"Save Tab as Window Arrangement"
@"Move to New Window"
@"Close Other Tabs"
@"Close Tabs Below" / @"Close Tabs to the Right"
@"Unpin Tab" / @"Pin Tab"
@"Tab Color"
```

#### iTermTextViewContextMenuHelper.m（ターミナル右クリック）

```objc
@"Look Up in Dictionary"
@"Quick Look"
@"Copy"
@"Paste"
@"Save"
@"Select All"
```

#### iTermProfilesMenuController.m（プロファイルメニュー）

- プロファイル名はユーザー定義（翻訳対象外）
- ただし `"Open All"` 等の固定文字列は翻訳対象

#### iTermStatusBarContainerView.m（ステータスバー）

```objc
@"Configure <component>"
@"Hide <component>"
@"Configure Status Bar"
@"Disable Status Bar"
```

#### MainMenuMangler.swift（メニューアイコン付与、macOS 26+）

200 以上のメニュー項目の identifier → SF Symbol マッピングを持つ。メニュータイトル自体は変更しないが、identifier 文字列が英語タイトルと一致している。

### 2.3 メニュー定義の分布

```
メニュー文字列の定義場所
├── MainMenu.xib（静的）           ≈ 59 項目
├── .strings ファイル（iTerm.strings 等） ≈ 124 項目
├── ソースコード（ハードコード）
│   ├── iTermApplicationDelegate.m  ≈ 15 項目
│   ├── PseudoTerminal.m            ≈ 18 項目
│   ├── iTermTextViewContextMenuHelper.m ≈ 6 項目
│   ├── PTYSession.m                ≈ 4 項目
│   ├── その他 10+ ファイル         ≈ 20 項目
│   └── 小計                        ≈ 63 項目
└── 合計                            ≈ 246 メニュー項目
```

---

## 3. ハードコード状態の調査結果

### 3.1 カテゴリ別ハードコード文字列数

| カテゴリ | .m ファイル | .swift ファイル | 合計 |
|---------|------------|---------------|------|
| アラート `messageText` | 76 | 25+ | ~100 |
| ボタンタイトル `addButtonWithTitle:` | 113 | 33 | ~146 |
| メニュー項目タイトル | 40+ | 23+ | ~63 |
| ツールバー/TouchBar ラベル | 10+ | 5+ | ~15 |
| `informativeText` | 52+ | 20+ | ~72 |
| **合計（重複含む）** | | | **~396** |

### 3.2 ハードコードが多いファイル TOP 10

| # | ファイル | UI 文字列数 | 内容 |
|---|---------|-----------|------|
| 1 | `PTYSession.m` | 22+ | アラート、tmux 関連メッセージ |
| 2 | `PseudoTerminal.m` | 18+ | タブメニュー、ウィンドウ操作 |
| 3 | `iTermApplicationDelegate.m` | 15+ | メインメニュー動的項目 |
| 4 | `iTermPythonRuntimeDownloader.m` | 10+ | Python ランタイムエラー |
| 5 | `iTermPasswordManagerWindowController.m` | 8+ | パスワード管理ダイアログ |
| 6 | `ProfilesColorsPreferencesViewController.m` | 8+ | カラープリセット |
| 7 | `FileTransferManager.m` | 6+ | ファイル転送アラート |
| 8 | `KeysPreferencesViewController.m` | 6+ | キーバインド設定 |
| 9 | `iTermTextViewContextMenuHelper.m` | 6+ | 右クリックメニュー |
| 10 | `LastPassDataSource.swift` | 6+ | LastPass 連携 |

### 3.3 高頻度の定型文字列

重複を除いた定型文字列で、一括翻訳可能なもの:

| 英語 | 出現回数 | 日本語候補 |
|------|---------|----------|
| `"OK"` | 20+ | `"OK"` |
| `"Cancel"` | 15+ | `"キャンセル"` |
| `"Error"` | 8+ | `"エラー"` |
| `"Close"` | 6+ | `"閉じる"` |
| `"Copy"` | 5+ | `"コピー"` |
| `"Paste"` | 4+ | `"ペースト"` |
| `"Delete"` | 3+ | `"削除"` |

### 3.4 ローカライズ困難なパターン

#### 文字列フォーマット（変数埋め込み）

```objc
// PTYSession.m
[NSString stringWithFormat:@"Force Detach from tmux session "%@"?", sessionName]

// iTermPythonRuntimeDownloader.m
[NSString stringWithFormat:@"tar failed with this message: %@", error]
```

日本語では語順が変わるため、`%@` の位置を調整する必要がある場合あり。

#### 長文の説明テキスト

```objc
// KeysPreferencesViewController.m (255+ 文字)
@"Emulate US Keyboard affects how key presses are interpreted..."
```

#### 動的に組み立てられるタイトル

```objc
// PseudoTerminal.m
title = closing ? @"Close Tabs Below" : @"Close Tabs to the Right";
```

---

## 4. 日本語化の対応方式

### 4.1 方式 A: .strings ファイル翻訳（XIB 連動部分）

**対象**: XIB から抽出された 453 エントリ

**手順**:
1. `Interfaces/` に `ja.lproj/` ディレクトリを作成
2. 既存の `.strings` ファイルをコピーし、value 部分を日本語に翻訳
3. Xcode プロジェクトに日本語ローカライズを追加
4. `tools/applyLocalization.sh` を更新して適用

```
Interfaces/
├── MainMenu.xib          ← Base（英語）
├── MainMenu.strings       ← 英語用（既存）
├── ja.lproj/
│   ├── MainMenu.strings   ← 日本語翻訳 ★新規作成
│   ├── PreferencePanel.strings
│   ├── AddressBook.strings
│   ├── iTerm.strings
│   ├── configPanel.strings
│   └── PseudoTerminal.strings
```

**MainMenu.strings の翻訳例**:

```
/* 日本語版 ja.lproj/MainMenu.strings */
"About iTerm" = "iTerm について";
"Bigger Font" = "フォントを大きく";
"Bring All To Front" = "すべてを手前に移動";
"Clear Buffer" = "バッファをクリア";
"Clear Scrollback Buffer" = "スクロールバックをクリア";
"Close Tab" = "タブを閉じる";
"Close Window" = "ウィンドウを閉じる";
"Copy" = "コピー";
"Edit" = "編集";
"Find" = "検索";
"Find Next" = "次を検索";
"Find Previous" = "前を検索";
"Find..." = "検索…";
"Help" = "ヘルプ";
"Hide Others" = "ほかを隠す";
"Hide iTerm" = "iTerm を隠す";
"Jump to Selection" = "選択部分へジャンプ";
"Log" = "ログ";
"Minimize Window" = "しまう";
"New Tab" = "新規タブ";
"New Window" = "新規ウィンドウ";
"Next Tab" = "次のタブ";
"Next Window" = "次のウィンドウ";
"OK" = "OK";
"Page Setup..." = "ページ設定…";
"Paste" = "ペースト";
"Preferences..." = "設定…";
"Previous Tab" = "前のタブ";
"Previous Window" = "前のウィンドウ";
"Print..." = "プリント…";
"Quit iTerm" = "iTerm を終了";
"Select All" = "すべてを選択";
"Services" = "サービス";
"Shell" = "シェル";
"Show All" = "すべてを表示";
"Smaller Font" = "フォントを小さく";
"Start" = "開始";
"Stop" = "停止";
"Toggle Toolbar" = "ツールバーの表示切替";
"View" = "表示";
"Window" = "ウィンドウ";
"iTerm Help" = "iTerm ヘルプ";
```

### 4.2 方式 B: ソースコードのハードコード文字列を NSLocalizedString 化

**対象**: ソース内の約 300〜400 個のハードコード文字列

**手順**:

1. `Localizable.strings`（または `iTerm.strings`）に翻訳テーブルを作成
2. ハードコード文字列を `NSLocalizedString` / `NSLocalizedStringFromTableInBundle` に置換
3. `ja.lproj/Localizable.strings` に日本語翻訳を記述

**変換例（Objective-C）**:

```objc
// Before:
alert.messageText = @"Force Detach?";
[alert addButtonWithTitle:@"OK"];
[alert addButtonWithTitle:@"Cancel"];

// After:
alert.messageText = NSLocalizedStringFromTableInBundle(
    @"Force Detach?", @"iTerm",
    [NSBundle bundleForClass:[self class]],
    @"Alert title for tmux force detach");
[alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(
    @"OK", @"iTerm",
    [NSBundle bundleForClass:[self class]], nil)];
[alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(
    @"Cancel", @"iTerm",
    [NSBundle bundleForClass:[self class]], nil)];
```

**変換例（Swift）**:

```swift
// Before:
alert.messageText = "Can't Find 1Password CLI"

// After:
alert.messageText = NSLocalizedString(
    "Can't Find 1Password CLI",
    tableName: "iTerm",
    bundle: Bundle(for: type(of: self)),
    comment: "Alert when 1Password CLI not found")
```

### 4.3 方式 C: メニュー項目の動的ローカライズ

プログラム的に生成されるメニュー項目を翻訳する方式。

**パターン 1**: 直接 `NSLocalizedString` を使用

```objc
// Before:
[[NSMenuItem alloc] initWithTitle:@"New Tab to the Right"
                           action:@selector(newTabToTheRight:)
                    keyEquivalent:@""];

// After:
[[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(
                        @"New Tab to the Right", @"iTerm",
                        [NSBundle bundleForClass:[self class]], nil)
                           action:@selector(newTabToTheRight:)
                    keyEquivalent:@""];
```

**パターン 2**: MainMenuMangler.swift の identifier は英語のまま維持

```swift
// identifier はローカライズ不要（内部識別子として使用）
// title のみがローカライズ対象
```

### 4.4 Xcode プロジェクト設定の変更

```
1. Project → Info → Localizations に "Japanese" を追加
2. CFBundleLocalizations に "ja" を追加
3. 各 .strings ファイルの File Inspector で Japanese を有効化
4. ja.lproj/ ディレクトリに翻訳済みファイルを配置
```

---

## 5. 対象文字列の全量見積もり

### 5.1 カテゴリ別見積もり

| カテゴリ | 対応方式 | ユニーク文字列数 | 工数 |
|---------|---------|---------------|------|
| XIB メニュー項目 | A: .strings 翻訳 | 59 | 小 |
| XIB 設定画面ラベル | A: .strings 翻訳 | 158 | 中 |
| XIB プロファイル管理 | A: .strings 翻訳 | 92 | 小 |
| XIB コンテキスト・ツールバー | A: .strings 翻訳 | 144 | 小 |
| ソースコード メニュー | B+C: NSLocalizedString 化 | ~63 | 中 |
| ソースコード アラート | B: NSLocalizedString 化 | ~100 | 大 |
| ソースコード ボタン | B: NSLocalizedString 化 | ~30（重複除去後） | 小 |
| ソースコード 説明テキスト | B: NSLocalizedString 化 | ~72 | 大 |
| **合計** | | **~718** | |

### 5.2 メニュー限定の見積もり

**メニューの日本語化のみ**に絞った場合:

| 対象 | 文字列数 | 方式 |
|------|---------|------|
| MainMenu.strings（XIB メニュー） | 59 | .strings 翻訳のみ |
| iTerm.strings（コンテキストメニュー等） | 124 | .strings 翻訳のみ |
| ソースコード動的メニュー | ~63 | NSLocalizedString 化 + 翻訳 |
| **メニュー合計** | **~246** | |

---

## 6. 優先度別の作業計画

### Phase 1: メインメニューバーの日本語化（最小工数）

**対象**: `MainMenu.strings` の 59 エントリ
**方式**: .strings 翻訳のみ（コード変更なし）
**作業**:
1. `Interfaces/ja.lproj/` を作成
2. `MainMenu.strings` をコピーして value を日本語に翻訳
3. Xcode プロジェクトに ja ローカライズを追加

**効果**: メニューバーの File/Edit/View/Shell/Session/Window/Help がすべて日本語化

### Phase 2: コンテキストメニューとツールバーの日本語化

**対象**: `iTerm.strings` の 124 エントリ + `PseudoTerminal.strings`
**方式**: .strings 翻訳
**作業**:
1. `ja.lproj/iTerm.strings` を作成・翻訳
2. 既存の `NSLocalizedStringFromTableInBundle` が参照するテーブルが `iTerm.strings` なので、自動的に翻訳が適用される

### Phase 3: 動的メニュー項目の NSLocalizedString 化

**対象**: ソースコード内のハードコードメニュー文字列（~63 項目）
**方式**: コード変更 + .strings 翻訳
**主要ファイル**:
- `iTermApplicationDelegate.m`（15 項目）
- `PseudoTerminal.m`（18 項目）
- `iTermTextViewContextMenuHelper.m`（6 項目）
- `PTYSession.m`（4 項目）
- `iTermStatusBarContainerView.m`（4 項目）
- その他 10+ ファイル

### Phase 4: 設定画面の日本語化

**対象**: `PreferencePanel.strings`（158 項目）+ `AddressBook.strings`（92 項目）
**方式**: .strings 翻訳

### Phase 5: アラート・ダイアログの日本語化

**対象**: ソースコード内のアラート文字列（~170 項目）
**方式**: 全ハードコード文字列を NSLocalizedString 化 + 翻訳
**注意**: 最も工数が大きく、フォーマット文字列の語順調整が必要

---

## 付録: 主要ファイルパス一覧

### ローカライズ関連

| 種類 | パス |
|------|------|
| メインメニュー XIB | `Interfaces/MainMenu.xib` |
| メインメニュー strings | `Interfaces/MainMenu.strings` |
| 設定画面 strings | `Interfaces/PreferencePanel.strings` |
| プロファイル strings | `Interfaces/AddressBook.strings` |
| 汎用 strings | `Interfaces/iTerm.strings` |
| 設定パネル strings | `Interfaces/configPanel.strings` |
| ターミナル strings | `Interfaces/PseudoTerminal.strings` |
| ローカライズツール | `tools/applyLocalization.sh` |

### メニュー生成ソースコード

| ファイル | 内容 |
|---------|------|
| `sources/iTermApplicationDelegate.m` | メインメニュー動的項目 |
| `sources/PseudoTerminal.m` | タブ右クリック、ウィンドウメニュー |
| `sources/iTermTextViewContextMenuHelper.m` | ターミナル右クリック |
| `sources/iTermProfilesMenuController.m` | プロファイルメニュー |
| `sources/PTYSession.m` | セッション関連メニュー |
| `sources/iTermStatusBarContainerView.m` | ステータスバーメニュー |
| `sources/MainMenuMangler.swift` | メニュー SF Symbol 付与 |
| `sources/NSMenu+iTerm.swift` | メニューユーティリティ |

### ロケール関連

| ファイル | 内容 |
|---------|------|
| `sources/iTermLocaleGuesser.swift` | ロケール検出 |
| `sources/iTermLocalePrompt.swift` | ロケール選択ダイアログ |
| `sources/NSLocale+iTerm.h/m` | ロケールユーティリティ |
