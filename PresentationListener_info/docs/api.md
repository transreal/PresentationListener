## セッション制御

### StartListener[opts]
音声録音・書き起こし・AI 解説セッションを開始する。ffmpeg で連続録音し、1 秒ごとの tick で Whisper→Claude パイプラインを駆動する。新規ノートブックを作成して解説を書き込む。タイトルが読み取れた時点でノートブックを SourceVault フォルダへ `yyyymmdd-<タイトル>-presentation.nb` として保存・参照登録する。
→ "Started." (成功) | "Already running." | エラーメッセージ文字列 (失敗; `$lastStartMsg` にも格納)
Options: "Device" -> Automatic (音声デバイス名。Automatic なら `$cfgDevice`、それも Automatic なら既定マイクを自動解決; `ListAudioDevices[]` で一覧), "VideoDevice" -> Automatic (映像デバイス名。Automatic なら `$cfgVideoDevice`、それが Automatic なら最初の映像デバイス。None で映像なし; `ListVideoDevices[]` で一覧), "Language" -> Automatic (発表言語。Automatic で Whisper が自動判定。"ja" / "en" などの ISO コード、または "English" などの言語名), "OutputLanguage" -> Automatic (タイトル・解説・Q&A の出力言語。Automatic で `$Language`。発言が別言語なら訳も併記), "AudioOnly" -> Automatic (True で音声のみ: カメラを開かない。False で画像+音声。Automatic なら `$ListenerAudioOnly` の現在値を維持。解決済みの映像デバイスは保持され、途中で画像+音声へ戻せる), "ChunkDuration" -> 60 (録音セグメント長 [秒]), "MinParagraphLength" -> 80 (解説生成を起動する累積文字数しきい値), "CaptureInterval" -> 15 (スライドキャプチャ間隔 [秒]), "SlideThreshold" -> 0.08 (フレーム間差分でスライド変化を検出するしきい値 0–1), "SourceVaultSync" -> True (SourceVault への同期記録), "AutoCropSlide" -> False (True で室内スクリーン領域を自動クロップ; 誤検出リスクあり), "SlideMaxWidth" -> 1280 (スライド画像の最大幅 [px]), "NotebookFolder" -> Automatic (保存先フォルダ。Automatic で `SourceVault`$SourceVaultDefaultNotebookFolder` → `$onWork` → 前に保存したフォルダ → `~/Dropbox/On Work` → `$packageDirectory` → `$UserDocumentsDirectory` の順で解決)
失敗条件: ffmpeg 未検出 / 音声デバイス未解決 / OpenAI キー未登録または取得拒否 / 一時ディレクトリ作成失敗 / 録音プロセス起動失敗
例: `StartListener["Device" -> "audio=Microphone Array", "VideoDevice" -> None, "Language" -> "en"]`
例: `StartListener["VideoDevice" -> "OBS Virtual Camera", "AutoCropSlide" -> True, "SlideMaxWidth" -> 800]`
例: `StartListener["Language" -> "English", "OutputLanguage" -> "Japanese"]`
例: `StartListener["AudioOnly" -> True]`

### StopListener[] → "Stopped."
録音プロセスと非同期 LLM を停止し、`VoiceQuestionStop[]` で音声質問セッションも閉じ、一時ファイルを削除する。未保存ノートブックを既定名 "presentation" で保存し、SourceVault に即時 index 化する。

### ResumeListener[] → "Resumed." | "Already running." | "No device."
`StopListener[]` 後に同じデバイス・設定で録音を再開する。ノートブックと transcript は引き継がれる。

## クエリ & エクスポート

### AskQuestion[q] → "質問を送信しました。" | "No notebook."
セッション全体の書き起こし・解説・スライドを文脈として Claude に質問を送信し、結果をノートブックに書き込む (非同期)。回答は出力言語で書かれる。`#N` でセクション番号指定が可能。SourceVault にも質問・回答を記録する。ノートブックがなければ "No notebook."。文字列以外は `ToString` される。
送るとすぐ「⏳ 回答を待っています… (経路)」を書き、回答が届いたら置き換える。⚡高速 (課金API 許可) では解説と同じく API (`$ListenerSummaryModel`) を直接呼び、🔧標準では `ClaudeQueryAsync` (CLI 優先)。🔧 で `$AskQuestionTimeout` 秒 (既定 600) 届かなければその旨のメモを書き (遅れて届いた回答も続けて書く)、⚡ の失敗・タイムアウトも「回答を取得できませんでした (理由)」として残る (黙って消えない)。`DiagState[]` の asks 行で待ち状況が見える。
スライド画像も添える: `#N` があればそのセクションの、無ければ質問の語と発言・解説の重なりで選んだ上位 2 セクションの (どれも合わなければ最後のセクションの) スライドを最大 4 枚、画像つきの問い合わせ (`ClaudeQueryAsync[{本文, Image…}, …]`) で送る。CLI 経路では添付ファイルとして読ませ、課金API 許可なら画像つきで API へ送る。計算・プロット・図の再現・数値例を求めると、自己完結の Wolfram Language コードが ```mathematica で返り、Input セルとして書かれる (Shift+Enter で評価できる。構文として読めないコードには注意のセルが付く)。回答の本文は Markdown + TeX を Mathematica のセルに組む。
例: `AskQuestion["#2 の定理と #3 の補題の関係を説明して"]`
例: `AskQuestion["ランク2格子の充填密度界の計算のスライドのプロットをMathematicaで再現してほしい。"]`
例: `AskQuestion["この発表全体の要点を 3 点でまとめて"]`

### GetTranscript[] → String
セッション全体の書き起こしテキストを返す。空なら "(empty)"。

### GetSegments[] → List
解析済みセグメントのリストを返す。各要素は `<|"text" -> ..., "commentary" -> ..., "translation" -> ..., "time" -> ..., "timestamp" -> ..., "slides" -> {Image, ...}|>`。"translation" は発言が出力言語と異なるときの訳 (なければ "")。

### ExportSession[fn] → (ファイル書き込み)
セッション内容を Markdown ファイルとして書き出す。拡張子なしの場合 ".md" を付加する。

## 音声質問 (VoiceQuestion)

質問を発表者の言語へ翻訳 (LLM) → 音声で読み上げ → マイクを開いて発表者の声を書き起こし → 黙って `$VoiceQuestionSilence` 秒 (または `VoiceQuestionFinish[]`) で確定 → 原文セルを書き、出力言語へ訳したセルを続けて書く。読み上げ以外は音声モデルに話させない。SourceVault のロードとパレットの「課金API: 許可」が必要。

### VoiceQuestion[q] → String
質問 `q` を発表者の言語で音声読み上げし、声の回答を書き起こして出力言語 (`"OutputLanguage"` / `$Language`) のテキストセルとしてノートブックへ書く (非ブロック、`RunScheduledTask` で進行)。ノートブックがなければ新規作成する。文字列以外は `ToString` される。パレットの「🎤 Voice Q」と同じ。
→ "音声質問を開始しました。" | エラーメッセージ ("質問が空です。" / "前の音声質問がまだ終わっていません (VoiceQuestionFinish[] で回答を確定)。" / SourceVault_realtime 未ロード / 課金API 禁止 等)
例: `VoiceQuestion["この手法の計算量はどのくらいですか?"]`

### VoiceQuestionFinish[] → String
回答の聞き取りを今の時点で打ち切って出力する。聞き取り中なら "回答を確定します。"、それ以外は "回答待ちではありません。"。パレットでは回答待ちの間ボタンが「✓ 回答を確定」になる。

### VoiceQuestionStop[] → "Stopped."
音声質問を中止し、自分で開いた音声セッションを閉じる。

### VoiceQuestionStatus[] → Association
`<|"State" -> ..., "Status" -> ..., "Model" -> ..., "SpeakerLanguage" -> ..., "Spoken" -> ..., "OwnSession" -> ..., "Realtime" -> ...|>`。State は "idle" / "preparing" / "speaking" / "listening" / "translating"。

## まとめ (ListenerSummary)

その時点までの記録 (`GetSegments[]` の発言・解説、まだ解説の付いていない最新の発言、音声質問への発表者の回答) から、簡潔なまとめ・鍵になるポイント・追加情報がないと理解できない点 (質問案つき) を LLM に JSON で作らせ、Template (`Templates/SourceVault notebook template.nb`、スタイルシート `SourceVault default.nb`) 由来の別ノートへ書き出す。発表者の主張としてまとめるのは発言に根拠がある内容だけで、AI 解説は補足として扱う。

### ListenerSummary[opts] → String
非ブロックでまとめを作り、まとめノートを前面に出す。1 回の収録 (`StartListener`) につきまとめノートは 1 冊で、呼ぶたびに「まとめ — 経過 mm:ss 時点」の節を末尾に足す (前の節は残る)。収録を止めた後でも使える (経過は最後のセクションの時刻)。作成中にもう一度呼ぶと状況を返すだけ (600 秒返らなければ捨てて作り直す)。パレットの「📝 まとめ」と同じ。
- オプション `"Save" -> True`: presentation ノートが保存済みなら同じフォルダに `…-summary.nb`、未保存なら既定フォルダに `yyyymmdd-<推定題目>-summary.nb` として保存し、`SourceVaultRegisterNotebook` で登録してセッションにリンクする。2 回目以降は同じファイルへ上書き保存。
- ノートの構成: NotebookStatus (Keywords `{"presentation", "summary"}`、SessionID) / Title (推定題目) / 節ごとに Subsection → Subsubsection「要約」(Text)・「鍵になるポイント」(Item + Subitem、根拠セクション `(#n)`)・「追加情報がないと理解できない点」(Item `Q1 …` + Subitem「不足している情報」「質問案」、発言が出力言語と別なら「発表者の言語で」)。見出しは出力言語 (日本語以外は英語)。
- ⚡高速 (課金API 許可 + 高速モード): `$ListenerSummaryModel` を curl で直接呼ぶ (claude-opus-5 系などには effort "medium" と server-side fallback を付ける)。API エラー・無応答なら 🔧標準で 1 回取り直し、節の注記に残す。🔧標準: `ClaudeQueryAsync` (パレットのモデル、`AutoCellize -> False`)。
→ "まとめを作成しています…" | "まとめを作成中です…" | "まだまとめるほどの発言がありません。" | "まとめ用のノートを開けませんでした。"
例: `ListenerSummary[]`、`ListenerSummary["Save" -> False]`

## ノートブック処理

### ProcessCells[prompt]
### ProcessCells[prompt, nb]
指定ノートブック (省略時は `InputNotebook[]`) の選択セルをテキスト・画像として収集し、prompt に従って Claude に処理させ、結果をノートブックに書き込む (非同期)。選択なし、または prompt に「全体」「すべて」「ノートブック」を含む場合は全セルを対象とする。テキスト 12 万文字・画像 5 枚まで送信。ノートブックが無効なら `$Failed`。
例: `ProcessCells["この証明の誤りを指摘して"]`
例: `ProcessCells["Mathematica コードに変換して", InputNotebook[]]`

## デバイス管理

### ListAudioDevices[] → List
DirectShow 経由で利用可能な音声デバイスの一覧を返す。各要素は `<|"name" -> "...", "alt" -> "..."|>`。

### ListVideoDevices[] → List
DirectShow 経由で利用可能な映像デバイスの一覧を返す。各要素は `<|"name" -> "...", "alt" -> "..."|>`。

### CaptureNow[] → "Captured." | エラー文字列
現在のフレームを即時キャプチャして `$slideBuffer` に追加する。`$running` が False または映像デバイスが未設定なら失敗を返す。

### ShowSettings[] → Association
デバイス選択・キャプチャ設定のダイアログを表示し (ffmpeg 未検出や一覧が空の場合は理由も表示)、選択内容を `$cfgDevice` / `$cfgVideoDevice` / `$cfgCaptureIntv` / `$cfgSlideThresh` に保存する。パレットの Settings... と同じダイアログ。
→ `<|"Audio" -> ..., "Video" -> ..., "CaptureInterval" -> ..., "SlideThreshold" -> ..., "ResolvedAudio" -> ..., "ResolvedVideo" -> ...|>`

## 状態参照

### ListenerStatus[] → String
"Recording [MM:SS]" または "Stopped" を返す。

### ListenerRunningQ[] → True | False
録音中なら True を返す。

### ListenerSourceVaultSession[] → String | None
現在の SourceVault セッション ID を返す。SourceVault 同期 OFF または未開始なら None。`SourceVaultGetLiveTranscript` 等に渡せる。

## 診断 & テスト

### DiagState[] → Column
実行状態・モード・課金 API 許可・tick・デバイス・キュー長・エラー等の診断情報を Column で返す。`Print[DiagState[]]` で表示する。

### TestMic[sec, d] → ファイルパス | $Failed
デバイス `d` から `sec` 秒録音して WAV ファイルパスを返す。`sec` の既定は 5、`d` の既定は "" (空文字列なら `$Failed`)。

### TestWhisper[w] → String | $Failed
### TestWhisper[w, lang] → String | $Failed
WAV ファイル `w` を Whisper API に送り、書き起こしテキストを返す。`lang` の既定は "ja" (Automatic / 不明な値なら言語指定なしで自動判定)。API キー未登録なら `$Failed`。

### TestVideo[d] → {Image, Image} | $Failed
デバイス `d` からフレームをキャプチャし、`{元画像, スライド検出後画像}` を返す。

## パレット

### ShowPalette[]
Start / Stop / Capture / Question / Voice Q (回答待ち中は「回答を確定」) / 📝 まとめ (作成中は「⏳ まとめ中…」) / Process Cells ボタンと、モード (⚡高速/🔧標準)・モデル (Default/Opus/Sonnet)・エフォート・課金 API 許可の切替、Settings...、Diagnostics を含む浮動パレットを作成・表示する。`ClaudeCode`$iPaletteFallback` を True に設定してから開く。パレットから Start すると `$cfgDevice` / `$cfgVideoDevice` / `$cfgCaptureIntv` / `$cfgSlideThresh` の設定値を使用する (それ以外のオプションは既定値)。

## 状態変数

### $plFastMode
型: Boolean, 初期値: True
True かつ課金 API 許可 (`ClaudeCode`$iPaletteFallback` = True) の場合、curl による Anthropic API 直接呼び出し (高速パス) を使用する。いずれか False なら `ClaudeQueryAsync` 標準パス (CLI 優先) にフォールバックする。

### $plLLMTimeout
型: Number | Automatic, 初期値: Automatic
🔧標準の LLM 応答を待つ秒数 (見張りの期限)。Automatic なら `ClaudeCode`$ClaudeTimeout` + 60 (無効なら 1200 + 60)。過ぎるか、ジョブが応答なしに消えると諦めて idle に戻し (書き起こしは残し解説は省く)、以後届いた応答は捨てる。

### $plSVSession
型: String | None, 初期値: None
SourceVault セッション ID。`StartListener` 実行時に `"presentation-<YYYYMMDDHHmmss>"` (UTC) 形式で設定される (`"SourceVaultSync" -> False` なら None)。`ListenerSourceVaultSession[]` でも参照可能。

### $plSVSync
型: Boolean, 初期値: True
False にすると SourceVault への書き込みを全て無効化する。`StartListener["SourceVaultSync" -> False]` で設定される。

### $ListenerAudioOnly
型: Boolean, 初期値: False
True なら映像デバイスを開かず音声のみで動作する。`StartListener["AudioOnly" -> True | False]` で設定される (Automatic は現在値を維持)。

### $cfgDevice
型: String | Automatic, 初期値: Automatic
`ShowSettings[]` / パレット Settings で保存される音声デバイス設定。`StartListener` で `"Device" -> Automatic` 指定時に参照される。

### $cfgVideoDevice
型: String | None | Automatic, 初期値: Automatic
`ShowSettings[]` / パレット Settings で保存される映像デバイス設定。`StartListener` で `"VideoDevice" -> Automatic` 指定時に参照される。

### $cfgCaptureIntv
型: Number, 初期値: 15
`ShowSettings[]` / パレット Settings で保存されるスライドキャプチャ間隔 [秒]。パレットの Start が `"CaptureInterval"` に渡す。

### $cfgSlideThresh
型: Number, 初期値: 0.1
`ShowSettings[]` / パレット Settings で保存されるスライド変化検出しきい値。パレットの Start が `"SlideThreshold"` に渡す。

### $FFmpegPath
型: String | Automatic, 初期値: Automatic
使う ffmpeg.exe のフルパス。Automatic なら PATH → winget/scoop/choco の既知の場所の順に探す。未検出はキャッシュされず 10 秒ごとに再探索されるため、インストール後にカーネル再起動は不要。値を変えると即座に再探索する。

### $ListenerSummaryModel
型: String, 初期値: "claude-opus-5-5"
⚡高速モードで `ListenerSummary` と `AskQuestion` に使う Anthropic のモデル。🔧標準モードではパレットのモデルを使う。

### $AskQuestionTimeout
型: Number, 初期値: 600
`AskQuestion` の回答を待つ秒数。🔧標準でこれを過ぎても届かなければノートに知らせる。⚡高速では API 呼び出しの上限時間。

### 収録中の読み直し
状態変数は「まだ値が無いときだけ」(`plKeep`) 初期化されるので、収録中に `Get["PresentationListener.wl"]` で読み直しても録音・記録・ノート・パレットはそのまま続き、新しい定義に差し替わる (claudecode は読み直さない)。

### $VoiceQuestionModel
型: String | Automatic, 初期値: Automatic
音声質問の声のモデル。Automatic なら SlideWorkflow の音声モデル (`$SlideVoiceModel`、既定 "gpt-live-1")、SlideWorkflow 未ロードなら "gpt-live-1"。

### $VoiceQuestionSilence
型: Number, 初期値: 5
発表者が黙ってから回答を確定するまでの秒数。

### $VoiceQuestionNoAnswerSeconds
型: Number, 初期値: 40
何も聞こえないまま諦めるまでの秒数。

### $VoiceQuestionMaxSeconds
型: Number, 初期値: 180
1 回の回答を聞く上限秒数。

### $VoiceQuestionIdleSeconds
型: Number, 初期値: 120
最後の質問から、自分で開いた音声セッションを閉じるまでの秒数 (GPT-Live は接続時間で課金)。