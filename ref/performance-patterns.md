# iTerm2 パフォーマンス最適化パターン

iTerm2 のソースコードから抽出した、表示・入出力処理の高速化テクニック集。
自分のアプリへの応用を想定し、アーキテクチャの要点をまとめる。

---

## 目次

1. [全体アーキテクチャ](#1-全体アーキテクチャ)
2. [GPU レンダリングパイプライン](#2-gpu-レンダリングパイプライン)
3. [フレームレート制御と適応的更新](#3-フレームレート制御と適応的更新)
4. [入力処理パイプライン](#4-入力処理パイプライン)
5. [PTY 通信とデータフロー](#5-pty-通信とデータフロー)
6. [バッファリング戦略](#6-バッファリング戦略)
7. [バッファサイズ一覧と管理戦略](#7-バッファサイズ一覧と管理戦略)
8. [キーボード入力キューの詳細](#8-キーボード入力キューの詳細)
9. [バックプレッシャーとフロー制御](#9-バックプレッシャーとフロー制御)
10. [メモリ管理（プール・CoW・キャッシュ）](#10-メモリ管理プールcowキャッシュ)
11. [スレッドモデルとキュー設計](#11-スレッドモデルとキュー設計)
12. [コアレッシングとバッチ処理](#12-コアレッシングとバッチ処理)
13. [パフォーマンス計測基盤](#13-パフォーマンス計測基盤)
14. [ケーススタディ: `cat /dev/random` でも Ctrl+C が即座に効く理由](#14-ケーススタディ)
15. [設計原則まとめ](#15-設計原則まとめ)

---

## 1. 全体アーキテクチャ

```
┌──────────────┐    ┌──────────────┐    ┌───────────────┐    ┌──────────────┐
│  PTY Read    │───▶│  VT100       │───▶│  Token        │───▶│  Metal       │
│  (BG Thread) │    │  Parser      │    │  Executor     │    │  Renderer    │
│              │    │              │    │  (Mutation Q)  │    │  (Private Q) │
└──────────────┘    └──────────────┘    └───────────────┘    └──────────────┘
       ▲                                       │                     │
       │                                       ▼                     ▼
┌──────────────┐                        ┌───────────────┐    ┌──────────────┐
│  Keyboard    │                        │  Side Effects │    │  Display     │
│  Input       │───────────────────────▶│  (Main Q)     │    │  (60fps)     │
└──────────────┘                        └───────────────┘    └──────────────┘
```

**ポイント**: 各ステージが異なるキュー/スレッドで動作し、パイプライン並列を実現。

---

## 2. GPU レンダリングパイプライン

### 2.1 Metal による GPU アクセラレーション

| ファイル | 役割 |
|---------|------|
| `sources/Metal/iTermMetalDriver.m` | レンダリング全体のオーケストレーション |
| `sources/iTermMetalView.swift` | CVDisplayLink 連携・フレーム管理 |
| `sources/Metal/Shaders/iTermText.metal` | GPU インスタンシングによるテキスト描画 |

- CPU ベースの描画を完全に GPU にオフロード
- `ENABLE_PRIVATE_QUEUE 1` で描画処理をプライベートキューで実行し、メインスレッドを解放

### 2.2 テクスチャアトラス＆グリフキャッシュ

```
┌────────────────────────────────────┐
│         Texture Atlas              │
│  ┌──┬──┬──┬──┬──┬──┬──┬──┬──┬──┐  │
│  │A │B │C │...│z │! │@ │# │$ │% │  │
│  └──┴──┴──┴──┴──┴──┴──┴──┴──┴──┘  │
│  Regular / Bold / Italic variants  │
└────────────────────────────────────┘
```

- **ASCII グリフ事前レンダリング**: `iTermASCIITexture` で Regular/Bold/Italic を GPU テクスチャ配列にプリレンダ
- **LRU ページ退避**: `iTermTexturePageCollection` で使用頻度の低いページを自動退避しメモリ上限を維持
- **参照カウント**: テクスチャページは参照カウント方式で安全にメモリ解放

### 2.3 GPU インスタンシング

```metal
// iTermText.metal
vertex iTermTextVertexFunctionOutput
iTermTextVertexShader(uint iid [[instance_id]], ...) {
    // 1回のドローコールで全グリフを描画
    // per-instance uniform でグリフごとの位置・色を指定
}
```

**効果**: ドローコール数を劇的に削減（数千文字 → 1 ドローコール）

### 2.4 マルチパスレンダリング

1. **中間テクスチャ**: 背景色を合成
2. **テンポラリテクスチャ**: サブピクセルアンチエイリアシング用に背景をサンプリング
3. **最終パス**: テキスト描画

背景とテキストを分離することで、高品質なサブピクセル AA を GPU で実現。

---

## 3. フレームレート制御と適応的更新

### 3.1 CVDisplayLink によるディスプレイ同期

```swift
// iTermMetalView.swift
// CVDisplayLink でモニターのリフレッシュレートに同期
// DispatchSourceUserDataAdd で複数のリフレッシュ要求を1回の描画にコアレス
```

- スクリーンティアリング防止
- `DispatchSourceUserDataAdd` で複数の needsDisplay 要求を 1 フレームに集約

### 3.2 適応的フレームレート

```
スループット高  ──▶  60 fps（アクティブ描画）
スループット低  ──▶  30 fps or 20 fps（フレーム間隔除数）
アイドル状態    ──▶   1 fps（バックグラウンド）
低電力モード    ──▶  レート低下
ProMotion      ──▶  120 fps 対応
```

| ファイル | パターン |
|---------|---------|
| `iTermUpdateCadenceController.m` | スループットベースの適応的 FPS 切り替え |
| `iTermThroughputEstimator.m` | 指数重み付きバケットで直近スループットを推定 |

- **キー入力検知**: 直近のキー入力後は低スループットでも高 FPS を維持し、体感レスポンスを向上
- **GCD タイマー**: NSTimer より精度の高い `dispatch_source_t` を使用

### 3.3 レート制限付き更新

```objc
// iTermRateLimitedUpdate
// 2つのモード:
// - Suppression: 中間の呼び出しを無視
// - Deferred: アイドル後に最後の呼び出しを実行
```

**用途**: UI 更新ストーム防止、高頻度イベントの間引き

---

## 4. 入力処理パイプライン

### 4.1 キーボード入力 → PTY 書き込み

```
キー入力 → IME処理 → PTYTask.writeBuffer → TaskNotifier → PTY fd
```

- `writeBuffer` は `NSLock` で保護し、ロック保持時間を最小化
- 実際の `write()` はバックグラウンドスレッドで実行
- 1 回の write は最大 1024 バイト（`MAXRW`）に制限

### 4.2 VT100 パーサー最適化

| 最適化 | 詳細 |
|--------|------|
| **オブジェクトプール** | `iTermObjectPool` で VT100Token の alloc/dealloc を排除 |
| **CVector** | Obj-C のオーバーヘッドを避ける C ベースの固定容量ベクタ |
| **オフセットベース消費** | データコピーなしでバッファを消費（offset 追跡） |

```
// VT100Parser.h コメントより:
// "Because so many VT100Token*s are created and destroyed,
//  too much time is spent adjusting their retain counts.
//  Since an iTermObjectPool is used to avoid alloc/dealloc calls,
//  the retain counts aren't useful."
```

**教訓**: ホットパスでは Obj-C の retain/release すら無視できないコスト。C ベースのデータ構造で回避。

---

## 5. PTY 通信とデータフロー

### 5.1 読み取り戦略

```objc
// PTYTask.m - processRead()
// 1回の呼び出しで最大4回の read()、各回最大 1024 バイト
// → 合計 4KB 読み取り後に制御を返す
```

```
// PTYTask.m コメントより（2025年5月のベンチマーク結果）:
// "each read gives 1024 bytes and allows the PTY to fill
//  with the next 1024 bytes. That becomes the steady state."
```

**設計意図**: 読み取りと PTY バッファ充填を交互に行い、スループットを最大化しつつ他の処理をブロックしない。

### 5.2 select() ループ

```
TaskNotifier (BG Thread)
    │
    ├── select() で全 PTY fd を監視
    ├── pipe ベースのシグナルで select() をウェイクアップ
    ├── NSRecursiveLock でタスクリスト保護
    └── deadpool で waitpid() 管理
```

---

## 6. バッファリング戦略

### 6.1 VT100ByteStream（ストリームバッファ）

| パラメータ | 値 |
|-----------|-----|
| 初期サイズ | 100 KB |
| 増分 | 最大 500 KB |
| 再確保閾値 | デフォルトサイズの 2 倍超 |

- **オフセットベースの消費**: データをコピーせず offset を進める
- **カーソル API**: ゼロコピーパーシング
- **適応的メモリ管理**: サイズが 2 倍を超えたら再確保してメモリを返却

### 6.2 LineBuffer（画面履歴）

- **ブロックベース格納**: 行をブロック単位で管理
- **ラッピング計算キャッシュ**: 折り返し計算を高速化
- **CoW セマンティクス**: リサイズ時の効率的な複製
- **部分行追加**: インクリメンタルな入力に対応

### 6.3 iTermTaskQueue（タスクデック）

- `os_unfair_lock` による最小オーバーヘッドのロック
- ベクタ of 配列の二層構造で O(1) エンキュー/デキュー
- アトミックフラグ操作対応

---

## 7. バッファサイズ一覧と管理戦略

### 7.1 バッファサイズ定数一覧

| コンポーネント | ファイル | サイズ | 用途 |
|---------------|---------|--------|------|
| `MAXRW` | `PTYTask.m:1` | **1,024 bytes** | 1回の read()/write() の上限 |
| processRead 合計 | `PTYTask.m:419` | **4 × 1,024 = 4 KB** | 1サイクルの最大読み取り量 |
| `kDefaultStreamSize` | `VT100ByteStream.h:12` | **100,000 bytes (≈98 KB)** | パーサーのストリームバッファ初期サイズ |
| ストリーム再確保閾値 | `VT100ByteStream.h:70` | **200,000 bytes** | これを超えると縮小再確保 |
| ストリーム増分 | `VT100ByteStream.h:79-101` | **最大 500 × 100KB** | 必要に応じて段階的に拡張 |
| `kMaxWriteBufferSize` | `PTYTask.m:221` | **10,240 bytes (10 KB)** | キーボード入力の書き込みバッファ上限 |
| `BLOCK_SIZE` | `LineBuffer.m:148` | **8,192 bytes (8 KB)** | 画面履歴のブロック単位 |
| `bufferDepth` | `iTermAdvancedSettingsModel.m:433` | **40 チャンク** | トークンキューの深度（ユーザー設定可） |
| 定常状態バッファ | 計算値 | **≈40 KB** | bufferDepth × MAXRW |

### 7.2 バッファ管理パターン

#### VT100ByteStream の適応的サイズ管理

```
初期確保: 100 KB
    │
    ├─ データ追加時に容量不足 → 段階的に拡張（最大 500 × 100KB）
    │   └─ 成長量 = MIN(500, 必要量 / 100KB) × 100KB
    │
    ├─ リセット時に 200KB 超 → 100KB に縮小再確保
    │   └─ メモリを OS に返却して肥大化を防止
    │
    └─ オフセットベース消費 → データコピーなしで先頭を消費
        └─ offset を進めるだけ。memmove 不要
```

#### writeBuffer の流量制御

```
writeBuffer (NSMutableData, 最大 10 KB)
    │
    ├─ writeBufferHasRoom → length < 10,240 ?
    │   ├─ YES → データを追加
    │   └─ NO  → 書き込みを待機（ペースト等の大量入力を制限）
    │
    └─ processWrite() で 1,024 bytes ずつ消費
        └─ 書き込み完了分を memmove で除去
```

#### LineBuffer のブロック管理

```
BLOCK_SIZE = 8,192 bytes
    │
    ├─ ページサイズの倍数 → メモリアラインメント最適
    ├─ 1ブロック ≈ 100〜200行を格納
    ├─ 非常に長い行 → ブロックを動的に拡張
    └─ 最大行数超過 → 古いブロックを破棄
```

### 7.3 OS の内部バッファとの関係

```
// PTYTask.m コメントより（2025年5月ベンチマーク）:
// TTY ドライバの内部バッファ = 1,024 bytes
// → MAXRW = 1,024 に合わせることで:
//   read() → 1024 bytes 取得 → PTY バッファ充填 → 次の read()
//   この交互動作が定常状態になる
```

**設計意図**: OS のバッファサイズに MAXRW を一致させ、読み取りとバッファ充填がパイプライン的に交互実行されるようにする。

---

## 8. キーボード入力キューの詳細

### 8.1 NSEvent から PTY への完全なデータフロー

```
NSEvent (keyDown)
    │
    ▼
iTermKeyboardHandler.keyDown:inputContext:
    ├─ キーバインディング照合 (iTermNSKeyBindingEmulator)
    │   └─ DefaultKeyBindings.dict を参照
    ├─ キーリピート検出: event.isARepeat
    │   └─ DECARM モード OFF → リピートイベントを破棄
    ├─ IME (マークテキスト) の追跡
    │   └─ hadMarkedTextBeforeHandlingKeypressEvent
    └─ キーマッパーに委譲
        ├─ iTermTermkeyKeyMapper
        ├─ iTermStandardKeyMapper
        └─ iTermModifyOtherKeysMapper
            │
            ▼
PTYSession.insertText: / writeTask:
    ├─ エスケープ処理 (必要に応じて)
    └─ ターミナルエンコーディングで NSData に変換
            │
            ▼
PTYTask.writeTask:(NSData)
    ├─ writeLock.lock()
    ├─ writeBuffer.appendData(data)
    ├─ writeLock.unlock()
    └─ UnblockTaskNotifier()  ← select() を即座に起こす
            │
            ▼
processWrite() [TaskNotifier スレッド]
    ├─ writeLock.lock()
    ├─ write(fd, buffer, min(length, 1024))
    ├─ memmove() で書き込み済み部分を除去
    └─ writeLock.unlock()
```

### 8.2 キーリピートの処理

```objc
// iTermKeyboardHandler.m:88-104
_keyIsARepeat = [event isARepeat];

// DECARM (Auto Repeat Mode) チェック:
if (_keyIsARepeat && !DECARM_enabled) {
    return;  // リピートイベントを破棄
}
// それ以外は通常のキー入力と同じパスで処理
```

- OS が生成するキーリピートイベントをそのまま活用
- DECARM モードで無効化可能
- 特別なキューイングやレート制限なし（OS のリピート速度に依存）

### 8.3 IME（日本語入力等）のハンドリング

```
通常のキー入力:   keyDown → insertText: → PTY
IME 入力中:       keyDown → marked text 更新 → 確定 → insertText: → PTY
```

| 状態 | 動作 |
|------|------|
| マークテキストなし | 通常のキー送信 |
| マークテキストあり | キーイベントを IME に委譲、PTY には送信しない |
| 確定時 | `insertText:` で確定文字列を PTY に送信 |

- `hadMarkedTextBeforeHandlingKeypressEvent` フラグで二重送信を防止
- IME カーソル色のカスタマイズ対応 (`KEY_IME_CURSOR_COLOR`)

### 8.4 ペースト操作の制御

```
ペースト要求
    │
    ▼
iTermPasteHelper
    ├─ ブラケットペーストモード → ESC[200~ ... ESC[201~ で囲む
    ├─ チャンク分割 + ディレイ
    │   ├─ "quickly": 高速（チャンクサイズ大）
    │   ├─ "slowly": 低速（チャンク間にディレイ）
    │   └─ "advanced paste": ユーザー設定
    ├─ シェル文字のエスケープ
    ├─ タブ → スペース変換
    └─ コマンドモード: シェルプロンプトを待ってから次行を送信
```

**writeBuffer の上限（10 KB）がペーストの流量制御として機能**: バッファが満杯なら `writeBufferHasRoom` が NO を返し、次のチャンク送信を待機。

### 8.5 キー入力のコアレッシング

キーストローク自体のコアレッシングは**行わない**（即時性が最優先）。
コアレッシングが行われるのは出力側のみ:

| レイヤー | コアレッシング |
|---------|-------------|
| キー入力 | なし（即座に writeBuffer へ） |
| VT100 トークン | TokenArrayGroup にまとめて GANG 実行 |
| 画面更新 | DispatchSourceUserDataAdd で 1 フレームに集約 |
| 副作用 | 33ms 間隔でバッチ実行 |

**設計思想**: 入力は遅延ゼロで処理し、出力側でのみバッチ化する。

---

## 9. バックプレッシャーとフロー制御

### 9.1 セマフォによるバックプレッシャー

```swift
// TokenExecutor.swift
let semaphore = DispatchSemaphore(value: bufferDepth)

// PTY 読み取りスレッド側:
semaphore.wait(timeout: .distantFuture)  // キューが満杯なら読み取りをブロック

// トークン消費後:
semaphore.signal()  // 空きスロットを通知
```

**効果**: パーサーが処理しきれない量のデータが PTY から溢れるのを防止。メモリ使用量を一定に保つ。

### 9.2 コマンドランナーのバックプレッシャー

```objc
// iTermCommandRunner.h
// 出力ハンドラが completion block を受け取り、
// 処理完了を明示的に通知 → バックグラウンドプロセスに圧力を伝搬
```

---

## 10. メモリ管理（プール・CoW・キャッシュ）

### 10.1 Metal バッファプール

```
┌──────────────────────────────────────┐
│         iTermMetalBufferPool         │
│                                      │
│  作成済みバッファを再利用             │
│  "Creating Metal buffers is very     │
│   slow" — コメントより               │
│                                      │
│  MixedSizePool:                      │
│  - サイズ順ソート + 二分探索          │
│  - ベストフィット選択                 │
│  - 容量超過時に最小バッファを退避     │
└──────────────────────────────────────┘
```

### 10.2 テクスチャプール

- `iTermTexturePool`: 特定サイズのテクスチャをプーリング
- `iTermPooledTexture`: dealloc 時にプールに返却するラッパー
- 世代スタンプで有効性を追跡

### 10.3 Copy-on-Write

```swift
// CopyOnWrite.swift
@propertyWrapper
struct CopyOnWrite<Storage: AnyObject & Cloning> {
    private let mutex = Mutex()
    private var box: Storage

    var wrappedValue: Storage {
        mutating get {
            mutex.sync {
                if !isKnownUniquelyReferenced(&box) {
                    box = box.clone()  // 共有時のみコピー
                }
                return box
            }
        }
    }
}
```

**用途**: `DeltaString` 等で文字列データの不要なコピーを回避。

### 10.4 キャッシュ一覧

| キャッシュ | ファイル | 戦略 |
|-----------|---------|------|
| 汎用 LRU | `iTermCache.m` | 双方向リスト + シリアルキュー |
| 画像 | `iTermImageCache.h` | バイト上限ベース、(名前, サイズ, 色) キー |
| 全角文字 | `iTermDoubleWidthCharacterCache.h` | 折り返し計算結果をキャッシュ |
| マーク | `MarkCache.swift` | 行番号 → マーク、dirty フラグ |
| 部分文字列 | `SubStringCache.swift` | サイズ 1 キャッシュ（直近の結果のみ） |
| グリフ | `iTermTexturePageCollection` | LRU ページ退避 |
| サブピクセル AA | `iTermSubpixelModelBuilder` | 色変換テーブルをキャッシュ |

---

## 11. スレッドモデルとキュー設計

### 11.1 Single-Writer アーキテクチャ

```
┌─────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Main Queue │     │  Mutation Queue  │     │  Private Queue  │
│  (UI更新)   │     │  (端末状態変更)   │     │  (Metal描画)     │
│             │◀───▶│                 │────▶│                 │
│  Side       │join │  Token          │     │  GPU            │
│  Effects    │     │  Execution      │     │  Rendering      │
└─────────────┘     └─────────────────┘     └─────────────────┘
```

- **Mutation Queue**: 端末状態の全変更をシリアルキューで実行
- **Main Queue**: UI 更新と副作用のみ
- **joined フラグ**: Mutation Queue を一時停止し、Main Queue から安全に状態を読み取る
- **アサーション**: `assertMainQueueSafe()`, `assertMutationQueueSafe()` で不正なキューからのアクセスを検出

### 11.2 ロック戦略

| ロック種類 | 用途 | 特徴 |
|-----------|------|------|
| `os_unfair_lock` | TaskQueue | 最小オーバーヘッド |
| `NSLock` | PTY writeBuffer | 短時間保持 |
| `NSRecursiveLock` | TaskNotifier | コールバック中の再入に対応 |
| `Mutex` (Swift) | CoW | sync ブロック |
| `DispatchSemaphore` | バックプレッシャー | スレッド間流量制御 |

---

## 12. コアレッシングとバッチ処理

### 12.1 トークンコアレッシング

```swift
// TwoTierTokenQueue.swift
// 連続するコアレス可能な TokenArray を VT100_GANG トークンに結合
// → パースされた複数チャンクを1回の実行で処理
```

### 12.2 副作用バッチング

```swift
// TokenExecutor.swift
// PeriodicScheduler: 1/30 fps（33.33ms 間隔）で副作用をバッチ実行
// - sideEffects: 即時キュー
// - deferred effects: 次の期間の50%時点にスケジュール
```

### 12.3 ディスプレイリフレッシュのコアレッシング

```swift
// iTermMetalView.swift
// DispatchSourceUserDataAdd で複数の needsDisplay をマージ
// → 1フレームにつき1回の描画
```

### 12.4 ダブルバッファリング

```objc
// iTermTemporaryDoubleBufferedGridController
// カーソル非表示時にグリッド状態をスナップショット
// - 暗黙モード: 0.2秒で期限切れ
// - 明示モード: 1.0秒で期限切れ（sync制御シーケンス）
// → 高速状態遷移時のちらつき防止
```

### 12.5 入力の集約

```swift
// TypingAggregator.swift
// 0.5秒のタイマーウィンドウで複数の編集通知を集約
```

---

## 13. パフォーマンス計測基盤

### 13.1 フレームごとのタイミング

```objc
// iTermMetalFrameData - 50以上のパフォーマンスマーカー
// EndToEnd, GPU, CPU, MainQueue, PrivateQueue 各ステージを計測
```

### 13.2 ヒストグラム

```swift
// iTermHistogram
// - リザーバサンプリング
// - パーセンタイル: min, p50, p75, p95, max
// - スパークライン表示
```

### 13.3 スループット推定

```objc
// iTermThroughputEstimator
// - 5秒の履歴ウィンドウ
// - 1/30秒バケット
// - 指数重み付き（直近ほど重い: 2x, 4x, 8x）
```

---

## 14. ケーススタディ: `cat /dev/random` でも Ctrl+C が即座に効く理由

大量出力中でもキーボード入力が即座に反映される仕組みは、上記パターンの総合的な成果。

### 14.1 読み取りと書き込みの完全分離

```
出力パス (Read):  PTY fd → processRead() → VT100Parser → TokenExecutor
入力パス (Write): キーボード → writeBuffer → processWrite() → PTY fd
                               (NSLock)
```

- **出力パス**: TaskNotifier スレッドで `processRead()` が最大 4KB を読み取り、トークン化
- **入力パス**: メインスレッドで `writeBuffer` にデータを追加し、`UnblockTaskNotifier()` で即座に通知
- 両パスは**独立したバッファとロック**を使用し、相互にブロックしない

### 14.2 select() ループの双方向監視

```c
// TaskNotifier.m
loop {
    FD_SET(fd, &rfds);  // 読み取り監視
    if (task.wantsWrite) {
        FD_SET(fd, &wfds);  // 書き込み監視
    }
    select(highfd+1, &rfds, &wfds, &efds, NULL);

    // 読み取り可能 → processRead()
    // 書き込み可能 → processWrite()
}
```

- 読み取りと書き込みが**同じ select() コール**で同時に監視される
- どちらか一方が ready になれば即座に処理

### 14.3 unblock パイプによる即時ウェイクアップ

```c
// TaskNotifier.m - シグナルセーフな通知
void UnblockTaskNotifier(void) {
    char dummy = 0;
    write(unblockPipeW, &dummy, 1);  // write(2) はシグナルハンドラ内でも安全
}
```

キーボード入力があると `UnblockTaskNotifier()` が呼ばれ、select() のブロックを即座に解除。

### 14.4 バックプレッシャーが生む"隙間"

```
cat /dev/random が大量データを生成
    │
    ▼
processRead() が 4KB 読み取り
    │
    ▼
TokenExecutor のセマフォが満杯 → processRead() がブロック
    │
    ▼
★ この瞬間、select() ループが解放される
    │
    ▼
writeBuffer に Ctrl+C があれば即座に processWrite() が実行
    │
    ▼
PTY fd に \x03 が書き込まれる → カーネルが SIGINT を送信
    │
    ▼
cat プロセスが終了
```

**核心**: バックプレッシャーのセマフォが processRead() をブロックすることで、select() ループに書き込み処理の機会が生まれる。読み取りが無制限だと書き込みが飢餓状態になるが、4KB 上限 + セマフォがそれを防ぐ。

### 14.5 キー入力の直通パス

```
Ctrl+C → keyDown: → writeLatin1EncodedData: → PTYTask.writeTask:
    → writeBuffer に追加（ロック保持: マイクロ秒）
    → UnblockTaskNotifier()
    → select() 解除
    → processWrite() で PTY に送信
```

キー入力はトークン実行パイプラインを**完全にバイパス**し、writeBuffer → PTY fd へ直行する。パーサーやレンダラーの負荷に関係なく、入力は常に即座にキューされる。

### 14.6 設計のポイント

| 要素 | 効果 |
|------|------|
| Read/Write パス分離 | 出力処理が入力をブロックしない |
| 読み取り上限 (4KB/回) | select() ループの応答性を保証 |
| セマフォバックプレッシャー | 読み取りブロック中に書き込み機会を確保 |
| unblock パイプ | select() の即時ウェイクアップ |
| カーネル SIGINT | Ctrl+C は PTY に書くだけでカーネルがシグナル送信 |

---

## 15. 設計原則まとめ

| # | 原則 | iTerm2 での適用例 |
|---|------|------------------|
| 1 | **バックプレッシャー最優先** | セマフォでトークンキュー深度を制限 |
| 2 | **全レイヤーでバッチ処理** | Read(4KB), Write(1KB), Token(GANG), SideEffect(33ms) |
| 3 | **適応的レート** | スループットに応じて 1〜60 fps を動的切り替え |
| 4 | **ゼロコピー** | オフセットベースのバッファ消費、CoW 文字列 |
| 5 | **高コスト操作をプール** | Metal バッファ、テクスチャ、コマンドランナー |
| 6 | **ホットパスでは ObjC を避ける** | CVector、iTermObjectPool で retain/release 排除 |
| 7 | **Single-Writer** | Mutation Queue で状態変更を集約、joined で安全に読み取り |
| 8 | **遅延評価** | CoW、DeferredSideEffect、スナップショット期限切れ |
| 9 | **コアレッシング** | DispatchSourceUserDataAdd、TokenGroup、TypingAggregator |
| 10 | **計測駆動** | ヒストグラム・タイミングで定量的にボトルネックを特定 |

---

## 応用ガイド

自分のアプリに適用する際の優先順位:

1. **まずバックプレッシャーを実装**: データ生産側と消費側の速度差を制御
2. **適応的更新レートを導入**: アイドル時の無駄な描画を削減
3. **ホットパスのプロファイル**: retain/release やメモリ確保のコストを計測
4. **プーリング**: 頻繁に生成・破棄するオブジェクトをプール化
5. **コアレッシング**: 高頻度イベントを集約してから処理
6. **GPU オフロード**: 描画処理が CPU ボトルネックなら Metal/Vulkan へ移行
