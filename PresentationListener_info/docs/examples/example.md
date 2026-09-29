# PresentationListener — 使用例集

PresentationListener パッケージの代表的な使用パターンをまとめています。

---

## 例 1: 基本的なリスナーの起動と停止

講義やプレゼン中にリスナーを起動し、録音・解説を開始します。

```mathematica
(* パッケージをロード *)
Get["PresentationListener.wl"]

(* リスナーを起動 *)
StartPresentationListener[]
```

**期待される動作**: ノートブックに「録音中…」セクションが追加され、音声キャプチャが開始されます。

---

## 例 2: リスナーの停止とセッション終了

```mathematica
(* リスナーを停止 *)
StopPresentationListener[]
```

**期待される動作**: 録音が停止し、これまでの解説がノートブックに保存されます。

---

## 例 3: プレゼン内容への質問（AskQuestion）

録音中または停止後に、蓄積されたコンテキストに基づいて質問できます。

```mathematica
(* プレゼン内容について質問する *)
AskQuestion["スライドで説明されたアルゴリズムの計算量は何ですか？"]
```

**期待される動作**: これまでの録音・スライド内容をもとに Claude が回答し、ノートブックの新規セルに書き込まれます。

---

## 例 4: セッションのエクスポート

録音した内容・解説・Q&A をまとめてファイルに出力します。

```mathematica
(* セッションを JSON ファイルとしてエクスポート *)
ExportSession[]
```

**期待される動作**: `PresentationSession_<日時>.json` が NotebookDirectory[] に生成されます。

---

## 例 5: ⚡高速モードの有効化

curl による Anthropic API 直接呼び出しで応答速度を上げます。

```mathematica
(* 高速モードを ON にしてから起動 *)
$PLFastMode = True;
StartPresentationListener[]
```

**期待される動作**: ClaudeQueryAsync (CLI 経由) の代わりに curl が使用され、レイテンシが低減します。

---

## 例 6: SourceVault へのノート自動保存

SourceVault セッションと連携し、解説をベクトル DB に蓄積します。

```mathematica
(* SourceVault セッションを指定してからリスナーを起動 *)
$plSVSession = SVOpenSession["lecture-2026-06"];
StartPresentationListener[]
```

**期待される動作**: 各スライド解説が SourceVault に自動インデクスされ、後から意味検索できます。

---

## 例 7: ノートブックセルの一括 AI 解説（ProcessCells）

既存のノートブックセルに対して事後的に解説を追加します。

```mathematica
(* 現在のノートブックの入力セルすべてを処理 *)
ProcessCells[EvaluationNotebook[]]
```

**期待される動作**: 各コードセルの直後に Claude による解説セクションが挿入されます。

---

## 例 8: パレットから操作する

GUIパレットを使って起動・停止・質問を行います。

```mathematica
(* パレットを開く *)
PLOpenPalette[]
```

**期待される動作**: 「開始」「停止」「質問」ボタンを持つフローティングパレットが表示されます。ボタン操作だけで録音・解説サイクルを制御できます。

---