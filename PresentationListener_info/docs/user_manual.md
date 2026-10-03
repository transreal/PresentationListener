# PresentationListener ユーザーマニュアル

## 概要

PresentationListener は、講義・プレゼンテーション中の音声を継続録音し、スライド画像と組み合わせてリアルタイムに AI 解説をノートブックへ書き込むパッケージです。制御はコントロールパレットまたは公開 API 関数から行えます。Web カメラを使わず、音声だけを収録することもできます（後述の「収録モード（画像+音声 / 音声のみ）」を参照）。

発表言語は日本語に限りません。書き起こしは発表された言語のまま保存され、解説は出力言語（`$Language`）で生成されます。発表が出力言語と異なる場合は、発言の訳も併記されます。聴衆からの質問を発表者へ声で伝え、発表者の声の回答を文字で残す **音声質問（Voice Q）** にも対応しています。

---

## パレット（コントロールパネル）

### ShowPalette

パレットウィンドウを表示します。

```mathematica
ShowPalette[]
```

パレットは画面右端に常時表示され、録音の開始・停止・設定変更をワンクリックで操作できます。Palettes メニューの **Presentation Listener** からも起動できます。

**パレット上のボタン一覧**

| ボタン | 機能 |
|--------|------|
| `▶ Start` | リスナー録音を開始します |
| `■ Stop` | 録音を停止します |
| `Capture` | 現在のスライドを手動キャプチャします |
| `? Question` | 質問ダイアログを開きます（文字による質問） |
| `🎤 Voice Q` | 音声質問ダイアログを開きます。回答待ちの間は `✓ 回答を確定` に変わります |
| `▶ Process` | セル処理ダイアログを開きます |
| `収録: 画像+音声 / 音声のみ` | 収録モードを切り替えます（「設定」欄の先頭。録音中も可） |
| `Settings...` | 詳細設定ダイアログを開きます |
| `Diagnostics` | 診断情報を出力します |

`🎤 Voice Q` の下には、音声質問の進行状況（「音声質問を開始しました。」など）が小さく表示されます。

---

## 録音制御

### StartListener

プレゼンテーションリスナーを開始します。

```mathematica
StartListener[]
StartListener[
  "Device"          -> "MacBook Proのマイク",
  "VideoDevice"     -> "FaceTime HD Camera",
  "CaptureInterval" -> 5,
  "SlideThreshold"  -> 0.15
]

(* 音声のみで開始する *)
StartListener["AudioOnly" -> True]
```

| オプション | 型 | 説明 |
|---|---|---|
| `"Device"` | String | 使用するオーディオデバイス名 |
| `"VideoDevice"` | String | スライドキャプチャ用カメラデバイス名 |
| `"CaptureInterval"` | Integer | キャプチャ間隔（秒） |
| `"SlideThreshold"` | Real | スライド変化検出の閾値（0〜1） |
| `"Language"` | String / Automatic | 発表言語（後述の「発表言語と出力言語」を参照） |
| `"AudioOnly"` | True / False / Automatic | `True` で Web カメラを使わず音声のみ収録、`False` で画像+音声。`Automatic`（既定）は現在の `$ListenerAudioOnly` の値を使います |
| `"ChunkDuration"` | Integer | 録音を区切る長さ（秒、既定 60） |
| `"MinParagraphLength"` | Integer | 解説を生成する最小段落長（文字数、既定 80） |

オプションを省略すると、設定ダイアログで保存した値が使用されます。

録音・キャプチャには ffmpeg が必要です。見つからない場合は開始に失敗し、その理由がパレットに表示されます（後述の「ffmpeg の検出」を参照）。

---

### StopListener

録音を停止します。

```mathematica
StopListener[]
```

停止後、録音中に蓄積されたセグメントの最終処理が行われます。

---

## 収録モード（画像+音声 / 音声のみ）

既定では、音声に加えて Web カメラでスライド画像を収録します（**画像+音声**）。カメラが不要・使えない場合は、音声だけを収録・処理する **音声のみ** モードに切り替えられます。音声のみのときはカメラを開かず、スライド画像のキャプチャや差分判定も行いません。

### $ListenerAudioOnly

```mathematica
$ListenerAudioOnly          (* 既定: False = 画像と音声 *)
$ListenerAudioOnly = True   (* 音声のみ *)
```

`True` なら Web カメラを使わず音声だけを収録・処理します。パレット「設定」の `収録: …` ボタンで切り替えられ、`StartListener` の `"AudioOnly"` オプションで開始時に指定することもできます。収録中に切り替えた場合は、次のキャプチャから反映されます。

### ListenerSetAudioOnly

音声のみ収録 / 画像と音声の収録を切り替えます。収録中でも使えます。

```mathematica
ListenerSetAudioOnly[True]    (* 音声のみにする *)
ListenerSetAudioOnly[False]   (* 画像+音声にする *)
ListenerSetAudioOnly[]        (* 現在の状態を反転 (トグル) *)
```

- 停止中に呼ぶと、`$ListenerAudioOnly` を設定するだけで、`"音声のみ"` または `"画像+音声"` を返します。次回の開始時に反映されます。
- 収録中に `True` で呼ぶと、カメラの使用を止めて音声のみで続行します。
- 収録中に `False` で呼ぶと、映像デバイスを解決し直して画像収録へ戻します。このとき、スライドの差分判定は初期化されます。
- 切り替えると、ノートブックに「収録: 音声のみ」「収録: 画像+音声」といった記録が小さく書き込まれます。画像+音声へ戻そうとして映像デバイスが見つからない場合は、「画像+音声 (映像デバイスが見つからないため音声のみ)」と記録され、音声のみのまま続きます。
- 戻り値は `"音声のみ"` / `"画像+音声"`、収録中に映像デバイスが無いときは `"映像デバイスなし"` です。

### パレットでの切り替え

パレットの「設定」欄の先頭にある `収録: 画像+音声` / `収録: 音声のみ` をクリックするたびに切り替わります（音声のみのときは紫色で表示されます）。`▶ Start` ボタンで開始した場合も、このときの収録モードが使われます。

### 音声のみのときの注意

- `Capture`（`CaptureNow[]`）は使えず、「音声のみ収録中です (パレットの「収録」で画像+音声に切り替え)」と表示されます。
- 音声のみで開始しても、解決した映像デバイスは保持されるため、途中で画像+音声へ戻せます。

---

## キャプチャ・質問

### CaptureNow

現在のスライド画面を即時キャプチャします。

```mathematica
CaptureNow[]
```

録音中・停止中を問わず使用できます。キャプチャ画像はセッションに記録されます。音声のみ収録中は、キャプチャは行われません。

---

### AskQuestion

現在のスライド・文脈に対して質問を送信し、回答をノートブックに挿入します。

```mathematica
AskQuestion["この定理の証明を詳しく説明してください"]
```

引数なしで呼び出すと入力ダイアログが開きます。

```mathematica
AskQuestion[]
```

回答は固定の日本語ではなく、出力言語（`$Language`）で生成されます。

---

## 音声質問（Voice Q）

音声質問は、聴衆からの質問を発表者へ **声で** 伝え、発表者の **声の回答を書き起こして** ノートブックに残す機能です。

### 使い方

1. パレットの `🎤 Voice Q` をクリックし、質問文を入力（または確認）します。
2. パッケージの取り次ぎ役（音声モデル `gpt-live-1`）が、質問を発表者へ読み上げます。
3. 読み上げが終わると、発表者の回答の受付が始まります。パレットのボタンは `✓ 回答を確定` に変わります。
4. 発表者が回答し終えたら `✓ 回答を確定` をクリックします。回答が書き起こされ、質問と回答がノートブックに書き込まれます。

```mathematica
(* 回答の受付を終えて確定する (パレットの ✓ 回答を確定 と同じ) *)
VoiceQuestionFinish[]
```

回答待ちでない状態で呼ぶと、「回答待ちではありません。」と表示されます。

### 動作の詳細

- **質問は原文のまま読まれます。** 取り次ぎ役は、聴衆から発表者への質問を、書かれたとおりの言語と文言で伝えます。質問に自分で答えることはしません。
- **発表者の言語への翻訳。** 発表者の言語の手がかりがある場合、質問はまず発表者の言語へ翻訳されます。手がかりが無い場合は質問をそのまま読み上げます。質問と出力言語が同じ文字種（日本語・韓国語・中国語）のときは、翻訳を省いて待ち時間なしで読み上げます。翻訳は短いため、⚡高速モードでは解説と同じ curl 直接呼び出し、🔧標準モードでは `ClaudeQueryAsync` で行われます。
- **読み上げ以外は話しません。** 待機中はマイクを閉じ、回答中も取り次ぎ役は返事・相づち・お礼・要約・感想を言いません。発表者の回答が読み上げの途中で始まった場合は、取り次ぎ役が話し出したら止められます（発話の割り込みは 3 秒に 1 回まで）。
- **回答の集計。** 読み上げが終わった後の発話だけが回答として扱われます。回答の書き起こしは、途中で履歴が切れないよう逐次集めて保持します。
- **ミュート状態の復元。** 音声質問のために借りたセッションは、終了後に元のミュート状態へ戻されます。

### 必要条件

- OpenAI API キー（`OPENAI_API_KEY`）が登録されていること。
- パレットの **課金API: 許可** が有効であること。音声質問ではノート単位の承認は求めず、パレットの設定で課金の承認を受けます。
- ffmpeg が利用できること。

---

## 発表言語と出力言語

| 項目 | 役割 |
|---|---|
| 出力言語（`$Language`） | 解説・質問への回答・タイトルを書く言語 |
| 発表言語（`"Language"` オプション） | 音声認識（Whisper）に伝える発表の言語 |

- **書き起こしは言語を変えません。** 音声認識の誤り修正（同音異義語・聞き誤り・明らかな誤字の修正）は、発表された言語のまま行われます。文構造・語順・句読点は変えず、修正不要ならそのまま返します。翻訳は解説の生成時に行われます。
- **翻訳の併記。** 発言が出力言語と異なるときは、発言の訳も解説に併記されます。出力言語と同じ文字種のときは訳さずにそのまま出力します。原文が先に表示され、訳は届き次第続けて書き込まれます。
- **`"Language"` の指定。** 言語名（`"Japanese"`、`"English"`、`"Chinese"`、`"ChineseSimplified"`、`"ChineseTraditional"`、`"Arabic"`、`"Hindi"`、`"Indonesian"`、`"Vietnamese"`、`"Dutch"`、`"Polish"`、`"Turkish"` など）または言語コード（`"ja"`、`"zh"` など）を指定できます。`Automatic` にすると `language` を付けず、Whisper が自動判定します。
- **タイトル。** 解説の 1 行目に付くタイトルは、短い名詞句です（日本語なら 10〜25 文字）。英語など ASCII のタイトルは 1 文字あたりの情報量が少ないため、長めに残されます。単語の途中では切りません。

---

## ffmpeg の検出

ffmpeg の実行ファイルは PATH だけに頼らず、次の順で探されます。winget などで入れた直後で PATH に反映されていない場合でも、再起動せずに使えます。

1. `$FFmpegPath` が文字列で設定されていればそのパス
2. PATH 上の `ffmpeg`
3. 既知のインストール先
   - `C:\ffmpeg\bin\ffmpeg.exe`
   - `C:\ProgramData\chocolatey\bin\ffmpeg.exe`
   - `C:\Program Files\ffmpeg\bin\ffmpeg.exe`
   - scoop の shims（`%USERPROFILE%\scoop\shims\ffmpeg.exe`）
   - WinGet のパッケージ（`%LOCALAPPDATA%\Microsoft\WinGet\Packages` 以下の `*FFmpeg*`）

検出結果はキャッシュされます。見つからなかった場合は 10 秒ごとに探し直します。

見つからない場合は、パレットに理由が表示されます。設定ダイアログ（Settings...）でデバイス一覧が空のときも、「ffmpeg (…) が dshow デバイスを 1 つも返しませんでした。」のように理由が表示されます。ffmpeg は dshow デバイス名を UTF-8 で出力しますが、これを 1 バイト 1 文字で受けて文字化けする問題は自動で補正されます（例：「マイク」）。

---

## セル処理・エクスポート

### ProcessCells

指定したセル範囲（または全セル）を再処理し、AI 解説を書き込みます。

```mathematica
ProcessCells[]
ProcessCells[nb, {startCell, endCell}]
```

| 引数 | 説明 |
|---|---|
| `nb` | 処理対象の `NotebookObject`（省略時は現在のノートブック） |
| `{startCell, endCell}` | 処理範囲のセルオブジェクト |

---

### ExportSession

セッションの録音・解説データを外部ファイルにエクスポートします。

```mathematica
ExportSession[]
ExportSession["output_session.json"]
```

引数なしの場合はファイル選択ダイアログが開きます。出力形式は JSON（ShiftJIS 安全なバイナリ処理済み）です。

---

## 状態確認・診断

### ListenerRunningQ

現在録音中かどうかを返します。

```mathematica
ListenerRunningQ[]
(* True または False *)
```

---

### ListenerStatus

現在の状態を人間が読める文字列で返します。

```mathematica
ListenerStatus[]
(* "Recording [00:03:42]" または "Stopped" *)
```

---

### DiagState

内部状態の診断情報を文字列で返します。トラブルシューティングに使用します。

```mathematica
Print[DiagState[]]
```

出力例：

```
Running: True | FastMode: False | Mode: standard
Device: MacBook Pro Microphone | VideoDevice: FaceTime HD Camera
Segments: 12 | SVSession: Active
```

映像デバイスの状態は、使用中なら `ON`、音声のみ収録なら `OFF 音声のみ`、映像デバイスが無いときは `OFF` と表示されます。

---

## パレット設定の詳細

パレット上のトグルボタンで、以下の設定をセッション中に切り替えられます。

### 収録（画像+音声 / 音声のみ）

「設定」欄の先頭のボタンです。クリックするたびに `収録: 画像+音声` と `収録: 音声のみ` が切り替わります。録音中でも切り替えられ、`$ListenerAudioOnly` と連動します。詳細は「収録モード（画像+音声 / 音声のみ）」を参照してください。

---

### 処理モード（⚡ / 🔧）

| 表示 | モード | 説明 |
|---|---|---|
| ⚡ 高速 | Fast Mode | Anthropic API を直接呼び出し、低遅延で解説を生成します |
| 🔧 標準 | Standard Mode | [claudecode](https://github.com/transreal/claudecode) CLI 経由で安定動作します |

高速モードは **課金API: 許可** が有効なときのみ選択できます。

---

### モデル選択

パレットの「モデル」ボタンをクリックするたびに切り替わります。

| 表示 | モデル |
|---|---|
| Default | 自動選択 |
| Opus | Claude Opus（高品質） |
| Sonnet | Claude Sonnet（バランス） |

---

### エフォートレベル

Opus モード時のみ有効です。「エフォート」ボタンで切り替えます。

| 表示 | レベル | 説明 |
|---|---|---|
| Low | 低 | 短い解説、高速 |
| Med | 中 | 標準（デフォルト） |
| High | 高 | 詳細な解説 |
| Max | 最大 | 最も詳細、低速 |

---

### 課金API 許可/禁止

**課金API: 許可** にすると Anthropic API への直接アクセスが有効になります。API キーが必要です。**禁止** にすると高速モードは自動的に無効になります。音声質問（Voice Q）もこの設定で課金の承認を受けます。

---

## 典型的なワークフロー

### 1. パレットを使った基本操作

```mathematica
(* パッケージをロードしてパレットを表示 *)
Needs["PresentationListener`"]
ShowPalette[]

(* パレットの ▶ Start をクリックして録音開始 *)
(* 講義終了後、■ Stop をクリック *)
```

### 2. コードからの操作

```mathematica
Needs["PresentationListener`"]

(* 録音開始 *)
StartListener[
  "Device" -> "MacBook Proのマイク",
  "CaptureInterval" -> 10
]

(* 途中でスライドを手動キャプチャ *)
CaptureNow[]

(* 質問を追加 *)
AskQuestion["先生が言及した定理の名前は何ですか？"]

(* 録音停止 *)
StopListener[]

(* セッションをエクスポート *)
ExportSession["lecture_20260610.json"]
```

### 3. 英語など日本語以外の発表

```mathematica
Needs["PresentationListener`"]

(* 発表言語を明示する *)
StartListener["Language" -> "English"]

(* 言語を指定せず Whisper の自動判定に任せる *)
StartListener["Language" -> Automatic]
```

書き起こしは英語のまま保存され、解説は出力言語で書き込まれます。発言の訳も併記されます。

### 4. 聴衆の質問を発表者へ声で伝える

1. 録音中に、パレットの `🎤 Voice Q` をクリックして質問を入力します。
2. 取り次ぎ役が質問を読み上げます。
3. 発表者が声で答えます。
4. `✓ 回答を確定` をクリックします。質問と回答の書き起こしがノートブックに残ります。

### 5. カメラを使わず音声だけを収録する

```mathematica
Needs["PresentationListener`"]

(* 音声のみで開始 *)
StartListener["AudioOnly" -> True]

(* 途中で画像+音声へ戻す *)
ListenerSetAudioOnly[False]

(* 再び音声のみにする / 切り替え (トグル) *)
ListenerSetAudioOnly[True]
ListenerSetAudioOnly[]
```

パレットの `収録: …` ボタンでも同じ切り替えができます。

### 6. SourceVault との連携

[SourceVault](https://github.com/transreal/SourceVault) がインストールされている場合、セッション終了時にノートが自動的に SourceVault へ保存されます。設定は Settings ダイアログで管理します。

---

## 注意事項

- 録音開始前に Mathematica がマイクへのアクセス許可を持っていることを確認してください。
- ffmpeg が見つからないと録音を開始できません。インストール直後でも `$FFmpegPath` を設定するか、既知のインストール先に置けば検出されます。
- `"CaptureInterval"` を短く設定するとシステム負荷が上昇します。初期値は 5〜10 秒を推奨します。
- 音声のみ収録中は `Capture` が使えません。スライド画像が必要なときは、`収録` ボタンまたは `ListenerSetAudioOnly[False]` で画像+音声へ戻してください。
- 高速モード（⚡）を使用するには、API キーが正しく設定されている必要があります。詳細は setup.md を参照してください。
- 音声質問（Voice Q）には、OpenAI API キーとパレットの「課金API: 許可」が必要です。
- `DiagState[]` の出力はサポートへの問い合わせ時に添付してください。

---

## 関連パッケージ

- [claudecode](https://github.com/transreal/claudecode) — Claude CLI との統合基盤
- [NBAccess](https://github.com/transreal/NBAccess) — ノートブックセル操作 API
- [SourceVault](https://github.com/transreal/SourceVault) — セッションノートの永続化