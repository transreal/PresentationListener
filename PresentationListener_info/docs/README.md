# PresentationListener

音声録音 (ffmpeg) → Whisper 書き起こし → Claude 解説生成 → Mathematica ノートブック記録 を自動化するパッケージです。発表言語は日本語に限らず、解説は出力言語 (`$Language`) で生成され、発言が別言語なら訳も併記されます。聴衆からの質問を発表者へ声で伝え、声の回答を文字で残す **音声質問 (Voice Q)** にも対応しています。

## 設計思想と実装の概要

PresentationListener は、「講義・プレゼンテーションの場において研究者が内容の理解と記録に集中できるよう、音声・映像キャプチャから AI 解説生成・ノートブック保存までの一連のパイプラインを完全自動化する」という思想のもとで設計されています。

### なぜこの設計か

従来、講義録は手動で取るか、録音ファイルを後から処理する二段階の作業が必要でした。本パッケージはその作業を **リアルタイム** で行い、発言・スライド・AI 解説を時系列で整理してノートブックに書き込みます。利用者はパレットの「Start」ボタンを押すだけで録音・書き起こし・解説生成が始まり、後から「AskQuestion」で深掘りできます。

### パイプラインの構造

録音は ffmpeg の `-f segment` オプションによって一定秒数 (既定 60 秒) ごとのセグメント WAV ファイルとして継続的に出力されます。1 秒ごとに実行される `tick[]` スケジュールタスクがセグメントの完成を検出し、Whisper (OpenAI API) に送信して書き起こしを取得します。累積文字数がしきい値 (`MinParagraphLength`、既定 80 文字) を超えた段階で Claude に解説生成を依頼し、結果を [NBAccess](https://github.com/transreal/NBAccess) 経由でノートブックのセルとして書き込みます。

映像デバイスが設定されている場合は DirectShow 経由でスライドのフレームキャプチャも行い、フレーム間差分 (`SlideThreshold`) でスライドが切り替わったことを検出して画像を Claude に添付することで、より文脈に即した解説を生成します。

ffmpeg の実行ファイルは PATH だけに頼らず、`$FFmpegPath`、PATH、既知のインストール先 (WinGet / scoop / Chocolatey など) の順に自動検出されます。winget で導入した直後で PATH が未反映の Mathematica セッションでも、再起動なしで利用できます。

### 多言語対応

発表言語 (`"Language"` オプション。Whisper に伝える言語) と出力言語 (`"OutputLanguage"` オプション / `$Language`。解説・Q&A・タイトルを書く言語) を分けて扱います。書き起こしは発表された言語のまま保存され、音声認識の誤り修正も同じ言語のまま行われます。発言が出力言語と異なるときは、解説に訳が併記されます (`GetSegments[]` の `"translation"` に格納されます)。

### 二つの処理モード

本パッケージは処理モードを二系統持っています。

- **⚡ 高速モード** (`$plFastMode = True`、課金 API 許可時のみ): `StartProcess[curl]` で Anthropic API に直接 POST し、`tick[]` 内のポーリングで完了を検出します。PowerShell や Claude Code CLI の起動コストがゼロになるため、低遅延での解説生成が可能です。内部状態マシンは `idle → transcribing → correcting → commenting → idle` の順で遷移します。
- **🔧 標準モード** (課金 API 禁止時、または明示切り替え時): [claudecode](https://github.com/transreal/claudecode) の `ClaudeQueryAsync` を使用し、Claude Code CLI 経由で安定した動作を提供します。状態マシンは `idle → transcribing → llmBusy(callback) → idle` で遷移します。

### 音声質問 (Voice Q)

`VoiceQuestion[q]` は、質問を発表者の言語へ翻訳 (LLM) し、音声で読み上げ、マイクを開いて発表者の声を書き起こし、回答を原文セルと出力言語への訳セルとしてノートブックに残します。読み上げ以外は音声モデルに話させず、回答が止まるか `VoiceQuestionFinish[]` で確定されます。音声ブリッジには [SourceVault_realtime](https://github.com/transreal/SourceVault_realtime) を使用するため、SourceVault のロードとパレットの「課金API: 許可」が必要です。

### SourceVault との統合

[SourceVault](https://github.com/transreal/SourceVault) が読み込まれている場合、各セグメントの書き起こし・解説・質問・回答が自動的にセッションイベントとして ingest されます。セッションは `presentation-<日時>` 形式の ID で管理され (`ListenerSourceVaultSession[]` で取得可能)、後からベクトル検索や要約取得が可能です。ノートブックの保存先も SourceVault の既定ノートブックフォルダに自動解決され、`SourceVaultRegisterNotebook` で参照登録されます。

### ノートブック保存戦略

セッション中、最初の解説セクションからタイトルが読み取れた時点で `yyyymmdd-<タイトル>-presentation.nb` というファイル名で保存されます。保存先は `"NotebookFolder"` オプションで指定でき、Automatic なら SourceVault の既定フォルダ → `$onWork` → `$packageDirectory` の順で解決されます。以後の書き込みは `NotebookSave` による差分更新のため、Mathematica のクラッシュ時にも内容が保持されます。セッション終了時には SourceVault に即時インデックス化されます。

### API キー管理

Whisper 用 OpenAI キーおよび Anthropic キーは [NBAccess](https://github.com/transreal/NBAccess) の `NBGetAPIKey` を通じて取得します。現行 NBAccess は `AccessLevel >= 1.0` を要求するため、パッケージ内部で `PrivacySpec -> <|"AccessLevel" -> 1.0|>` を明示的に指定しています。OpenAI キーが「未登録」なのか「登録済みだが取得拒否」なのかは、`StartListener[]` の失敗メッセージで区別されます。

---

## 詳細説明

### 動作環境

| 項目 | 要件 |
|------|------|
| Mathematica | 13.0 以上 |
| OS | Windows 11 |
| ffmpeg | 導入済みであること (音声・映像キャプチャ、セグメント録音、DirectShow デバイス列挙に使用。PATH 外でも既知の場所は自動検出) |
| curl | PATH が通っていること (Whisper / Anthropic API 直接呼び出しに使用) |
| [claudecode](https://github.com/transreal/claudecode) | 導入済みであること |
| [NBAccess](https://github.com/transreal/NBAccess) | 導入済みであること |
| [SourceVault](https://github.com/transreal/SourceVault) | 任意。セッション記録・ノートブック保存先解決に使用 |
| [SourceVault_realtime](https://github.com/transreal/SourceVault_realtime) | 任意。音声質問 (`VoiceQuestion`) に使用 |
| OpenAI API キー | Whisper 書き起こし用 |
| Anthropic API キー | Claude 解説生成用 |

> Windows 11 には標準で curl が含まれています。PowerShell で `curl --version` を実行して確認してください。
> macOS / Linux での動作検証は行っていません。

### インストール

#### 1. `$packageDirectory` の確認

```mathematica
$packageDirectory
```

未設定の場合は [claudecode](https://github.com/transreal/claudecode) の導入を先に完了させてください。

#### 2. ファイルの配置

`PresentationListener.wl` を `$packageDirectory` の**直下**に配置します。サブディレクトリには置かないでください。

```
<$packageDirectory>\PresentationListener.wl
```

#### 3. `$Path` の設定

[claudecode](https://github.com/transreal/claudecode) を使用している場合、`$Path` は自動的に設定されます。手動で設定する場合は以下を実行します。

```mathematica
If[!MemberQ[$Path, $packageDirectory],
  AppendTo[$Path, $packageDirectory]
]
```

> **注意**: `AppendTo[$Path, $packageDirectory]` が正しい形式です。`AppendTo[$Path, "C:\\path\\to\\PresentationListener"]` のようにパッケージ固有のパスを指定しないでください。

#### 4. パッケージのロード

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Needs["PresentationListener`", "PresentationListener.wl"]
]
```

#### 5. API キーの設定

[claudecode](https://github.com/transreal/claudecode) のキー管理機構を使用します。

```mathematica
(* OpenAI キー (Whisper 用) *)
SystemCredential["OPENAI_API_KEY"] = "sk-..."

(* Anthropic キー (Claude 用) *)
NBAccess`NBSetAPIKey["anthropic", "sk-ant-..."]
```

#### ffmpeg が見つからない場合

ffmpeg は winget などで導入できます (例: `winget install Gyan.FFmpeg`)。特定の実行ファイルを使いたい場合は、開始前に `PresentationListener`$FFmpegPath` を設定してください。詳細は setup.md を参照してください。

### クイックスタート

```mathematica
(* パッケージをロード *)
Block[{$CharacterEncoding = "UTF-8"},
  Needs["PresentationListener`", "PresentationListener.wl"]
]

(* 利用可能なデバイスを確認する *)
ListAudioDevices[]
ListVideoDevices[]

(* パレットを表示する (GUI 操作) *)
ShowPalette[]

(* --- または API で直接制御する --- *)

(* デバイスを選択してリスナーを開始する *)
StartListener[
  "Device"       -> "audio=Microphone Array",
  "VideoDevice"  -> None,
  "Language"     -> "ja",
  "ChunkDuration" -> 60,
  "MinParagraphLength" -> 80
]

(* 発表中に質問を送信する *)
AskQuestion["このスライドで説明された定理の証明を詳しく教えてください"]

(* セッションを停止する *)
StopListener[]

(* セッション内容を Markdown としてエクスポートする *)
ExportSession["lecture_notes"]
```

**主な設定変数・オプション**

| 変数 / オプション | 既定値 | 説明 |
|--------|--------|------|
| `$plFastMode` | `True` | 高速モード (curl 直接) の有効/無効 |
| `$plSVSync` | `True` | SourceVault 同期の有効/無効 |
| `$FFmpegPath` | (未設定) | ffmpeg 実行ファイルの明示パス |
| `"Language"` | `Automatic` | 発表言語 (ISO コードまたは言語名。Automatic で Whisper が自動判定) |
| `"OutputLanguage"` | `Automatic` | 解説・Q&A・タイトルの出力言語 (Automatic で `$Language`) |
| `"ChunkDuration"` | `60` | 録音セグメント長 (秒) |
| `"MinParagraphLength"` | `80` | 解説生成を起動する累積文字数しきい値 |
| `"CaptureInterval"` | `15` | スライドキャプチャ間隔 (秒) |
| `"SlideThreshold"` | `0.08` | スライド変化を検出するフレーム間差分しきい値 (0–1) |
| `"AutoCropSlide"` | `False` | スクリーン領域の自動クロップ |
| `"SlideMaxWidth"` | `1280` | スライド画像の最大幅 (px) |
| `"NotebookFolder"` | `Automatic` | ノートブック保存先フォルダ |

### 主な機能

#### セッション制御

- **`StartListener[opts]`** — 音声録音・書き起こし・AI 解説セッションを開始します。ffmpeg で連続録音し、1 秒ごとの tick で Whisper → Claude パイプラインを駆動します。新規ノートブックを作成して解説を書き込みます。
- **`StopListener[]`** — 録音プロセスと非同期 LLM を停止し、音声質問セッションも閉じ、一時ファイルを削除します。未保存ノートブックを既定名で保存し、SourceVault に即時インデックス化します。
- **`ResumeListener[]`** — `StopListener[]` 後に同じデバイス・設定で録音を再開します。ノートブックと書き起こしは引き継がれます。

#### クエリ & エクスポート

- **`AskQuestion[q]`** — セッション全体の書き起こし・解説・スライドを文脈として Claude に質問を送信し、結果を出力言語でノートブックに書き込みます (非同期)。`#N` でセクション番号を指定できます。
- **`GetTranscript[]`** — セッション全体の書き起こしテキストを返します。
- **`GetSegments[]`** — 解析済みセグメントのリストを返します。各要素は `<|"text" -> ..., "commentary" -> ..., "translation" -> ..., "time" -> ..., "timestamp" -> ..., "slides" -> {Image, ...}|>` の形式です。`"translation"` は発言が出力言語と異なるときの訳です。
- **`ExportSession[fn]`** — セッション内容を Markdown ファイルとして書き出します。

#### 音声質問 (Voice Q)

- **`VoiceQuestion[q]`** — 質問を発表者の言語で音声読み上げし、声の回答を書き起こして出力言語のセルとしてノートブックに書き込みます (非ブロック)。
- **`VoiceQuestionFinish[]`** — 回答の聞き取りを現時点で打ち切り、確定します。
- **`VoiceQuestionStop[]`** — 音声質問を中止し、自分で開いた音声セッションを閉じます。
- **`VoiceQuestionStatus[]`** — 現在の状態 (`idle` / `preparing` / `speaking` / `listening` / `translating` など) を Association で返します。

#### ノートブック処理

- **`ProcessCells[prompt]`** / **`ProcessCells[prompt, nb]`** — 指定ノートブック (省略時は `InputNotebook[]`) の選択セルをテキスト・画像として収集し、prompt に従って Claude に処理させ、結果をノートブックに書き込みます (非同期)。選択なし、または prompt に「全体」「すべて」「ノートブック」を含む場合は全セルを対象とします。

#### デバイス管理

- **`ListAudioDevices[]`** — DirectShow 経由で利用可能な音声デバイスの一覧を返します。
- **`ListVideoDevices[]`** — DirectShow 経由で利用可能な映像デバイスの一覧を返します。
- **`CaptureNow[]`** — 現在のフレームを即時キャプチャしてスライドバッファに追加します。
- **`ShowSettings[]`** — デバイス選択・キャプチャ間隔・スライドしきい値の設定ダイアログを開き、選択を保存して現在の設定を Association で返します。ffmpeg 未検出やデバイス一覧が空の場合は理由も表示されます。

#### 状態確認 & パレット

- **`ShowPalette[]`** — コントロールパレットを表示します。Start / Stop / Capture / Question / Voice Q / Process Cells ボタン、モード・モデル・エフォート・課金 API 許可の切替、Settings、Diagnostics を備えます。Palettes メニューの **Presentation Listener** からも起動できます。
- **`ListenerStatus[]`** — 現在の状態を人間が読める文字列で返します (`"Recording [00:03:42]"` または `"Stopped"`)。
- **`ListenerRunningQ[]`** — 現在録音中かどうかを `True` / `False` で返します。
- **`ListenerSourceVaultSession[]`** — 現在の SourceVault セッション ID を返します (同期 OFF・未開始なら `None`)。
- **`DiagState[]`** — 内部状態の診断情報を出力します。トラブルシューティングに使用します。

#### 診断・テスト

- **`TestMic[sec, d]`** — デバイス `d` から `sec` 秒録音して WAV ファイルのパスを返します。
- **`TestWhisper[w]`** / **`TestWhisper[w, lang]`** — WAV ファイルを Whisper に送り、書き起こしテキストを返します。
- **`TestVideo[d]`** — デバイス `d` からフレームをキャプチャし、元画像とスライド検出後画像を返します。

### ドキュメント一覧

| ファイル | 内容 |
|----------|------|
| [api.md](api.md) | 全公開関数のシグネチャ・オプション・戻り値リファレンス |
| [setup.md](setup.md) | 動作要件・インストール手順・ffmpeg 検出・API キー設定・トラブルシューティング |
| [user_manual.md](user_manual.md) | パレット操作・音声質問・発表言語と出力言語・各関数の詳細な使用方法 |
| [examples/example.md](examples/example.md) | 代表的な使用パターン集 (8 例) |

## 使用例・デモ

リポジトリ: [https://github.com/transreal/PresentationListener](https://github.com/transreal/PresentationListener)

### 例: 基本的な起動と停止

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Needs["PresentationListener`", "PresentationListener.wl"]
]

(* マイクのみ使用 (映像なし) *)
StartListener["Device" -> "audio=Microphone Array", "VideoDevice" -> None]

(* 発表終了後に停止 *)
StopListener[]
```

### 例: ビデオキャプチャ付きで起動する

```mathematica
(* OBS Virtual Camera でスライドをキャプチャしながら録音する *)
StartListener[
  "VideoDevice"    -> "OBS Virtual Camera",
  "AutoCropSlide"  -> True,
  "SlideMaxWidth"  -> 800
]
```

### 例: 英語の発表を日本語で解説する

```mathematica
(* 発表は英語、解説・Q&A は日本語。発言の訳も併記される *)
StartListener["Language" -> "English", "OutputLanguage" -> "Japanese"]
```

### 例: セッション中に質問する

```mathematica
(* 特定セクションの内容について深掘りする *)
AskQuestion["#2 の定理と #3 の補題の関係を説明して"]

(* 発表全体の要点をまとめさせる *)
AskQuestion["この発表全体の要点を 3 点でまとめて"]
```

### 例: 発表者へ音声で質問する

```mathematica
(* 質問を発表者の言語で読み上げ、声の回答を書き起こしてノートブックに残す *)
VoiceQuestion["この手法の計算量はどのくらいですか?"]

(* 回答が終わったら確定する (パレットの「✓ 回答を確定」と同じ) *)
VoiceQuestionFinish[]
```

### 例: SourceVault と連携する

```mathematica
(* SourceVault セッションを指定してから起動する *)
$plSVSession = "lecture-2026-06";
StartListener[]

(* 現在のセッション ID を確認する *)
ListenerSourceVaultSession[]
```

### 例: 既存ノートブックのセルを AI 処理する

```mathematica
(* 選択セルの証明に誤りがないか確認させる *)
ProcessCells["この証明の誤りを指摘して"]

(* テキストを Mathematica コードに変換させる *)
ProcessCells["Mathematica コードに変換して", InputNotebook[]]
```

### 例: 診断情報を確認する

```mathematica
Print[DiagState[]]
(* Running: True | FastMode: False | Mode: standard
   Device: Microphone Array | VideoDevice: None
   Segments: 5 | SVSession: Active ... *)
```

---

## 免責事項

本ソフトウェアは "as is"（現状有姿）で提供されており、明示・黙示を問わずいかなる保証もありません。
本ソフトウェアの使用または使用不能から生じるいかなる損害についても責任を負いません。
今後の動作保証のための更新が行われるとは限りません。
本ソフトウェアとドキュメントはほぼすべてが生成AIによって生成されたものです。
Windows 11上での実行を想定しており、MacOS, LinuxのMathematicaでの動作検証は一切していません(生成AIの処理で対応可能と想定されます)。

---

## ライセンス

```
MIT License

Copyright (c) 2026 Katsunobu Imai

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
