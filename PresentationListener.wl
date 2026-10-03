(* ::Package:: *)

(* ============================================================ *)
(*  PresentationListener.wl  v21                                *)
(*  claudecode.wl / NBAccess.wl 深層統合版                        *)
(*  v21 修正 (2026-05-30):                                       *)
(*    claudecode.wl のリファクタで パレット設定シンボル群が        *)
(*    Begin["`Private`"] の外 (= ClaudeCode` 直下) へ移動した。   *)
(*    本ファイルは旧構造前提で ClaudeCode`Private`$iPalette...   *)
(*    と参照していたため全て未定義シンボルを掴み、ShowPalette 冒頭 *)
(*    の iSavePaletteSettings 呼び出しが評価エラーで停止していた。 *)
(*    → パレット系参照を ClaudeCode` 直下に修正。                 *)
(*       ($iModelOpus/$iModelSonnet/iWriteQueryResponse は       *)
(*        Private のまま正しいので据え置き)                       *)
(*    あわせて StartListener の失敗理由を $lastStartMsg で可視化、 *)
(*    ffmpeg 存在チェック・録音起動検証を追加。                    *)
(*    モデル切替は iPaletteSyncClaudeModel[] 経由に統一。          *)
(*    v21b: NBGetAPIKey が AccessLevel>=1.0 を要求する現行仕様に   *)
(*    対応。whisperAPIKey/anthropicAPIKey で PrivacySpec を明示。  *)
(*  ⚡高速モード: v15スタイル直接curl + tickステートマシン          *)
(*    curl → Anthropic API 直接POST (PowerShell/iStartFallback不使用) *)
(*    状態: idle→transcribing→correcting→commenting→idle          *)
(*  🔧標準モード: ClaudeQueryAsync (CLI優先 + Fallback)          *)
(*    状態: idle→transcribing→llmBusy(callback)→idle              *)
(*  課金API禁止時: 高速モード無効→強制標準                        *)
(*  v22 (2026-09-26): 多言語プレゼン対応。                         *)
(*    発表言語は既定で Whisper 自動判定 ("Language"->Automatic)。 *)
(*    タイトル・解説・Q&A は $Language ("OutputLanguage") で出力し、 *)
(*    発言が出力言語と異なるときは発言の訳も併記する。             *)
(*  v22b (2026-09-27): ffmpeg を PATH 以外 (winget/scoop/choco,   *)
(*    $FFmpegPath) からも解決。未検出はキャッシュせず 10 s ごと再探索 *)
(*    (入れた後にカーネル再起動不要)。Settings は一覧が空の理由を表示。 *)
(*    dshow デバイス名の UTF-8 化け (マイク) を修正。               *)
(*  v23 (2026-09-27): VoiceQuestion (パレット「🎤 Voice Q」)。       *)
(*    質問を発表者の言語で音声読み上げ (SourceVault_realtime、       *)
(*    SlideWorkflow と同じ gpt-live)、声の回答を $Language で出力。   *)
(*  v23b (2026-10-02): パレット「収録: 画像+音声 / 音声のみ」トグル  *)
(*    ($ListenerAudioOnly / ListenerSetAudioOnly、収録中も切替可)。   *)
(* ============================================================ *)

Block[{$CharacterEncoding = "UTF-8"},
  Needs["ClaudeCode`", "claudecode.wl"]];

BeginPackage["PresentationListener`", {"ClaudeCode`", "NBAccess`"}];

StartListener::usage = "StartListener[\"Device\" -> \"audio\", \"VideoDevice\" -> \"video\"]\n\"Language\" -> Automatic (発表言語を Whisper が自動判定) | \"ja\" | \"en\" | \"English\" など。\n\"OutputLanguage\" -> Automatic ($Language) | \"English\" など。タイトル・解説はこの言語で出力し、発言が別言語なら訳も併記する。";
StopListener::usage = "StopListener[] 即座に停止 (非同期LLMも中断)";
AskQuestion::usage = "AskQuestion[\"質問\"]";
CaptureNow::usage = "CaptureNow[]";
ListAudioDevices::usage = "ListAudioDevices[]";
ListVideoDevices::usage = "ListVideoDevices[]";
ShowPalette::usage = "ShowPalette[]";
ShowSettings::usage = "ShowSettings[] はデバイス設定ダイアログ (音声/映像デバイス・capture 間隔・スライド閾値) を開き、選択を保存して現在の設定を Association で返す。ShowPalette の Settings... と同じダイアログ。StartListener 前のデバイス選択に使う。";
ListenerStatus::usage = "ListenerStatus[]";
ListenerRunningQ::usage = "ListenerRunningQ[]";
GetTranscript::usage = "GetTranscript[]";
GetSegments::usage = "GetSegments[]";
ExportSession::usage = "ExportSession[\"file.md\"]";
ListenerSourceVaultSession::usage = "ListenerSourceVaultSession[] は現在の SourceVault セッション ID を返す (融合 ON 時)。SourceVaultGetLiveTranscript 等に渡せる。";
TestMic::usage = "TestMic[n, device]";
TestWhisper::usage = "TestWhisper[wavFile]";
TestVideo::usage = "TestVideo[device]";
DiagState::usage = "DiagState[]";
ProcessCells::usage = "ProcessCells[\"prompt\"]";
$ListenerAudioOnly::usage = "$ListenerAudioOnly は True なら Web カメラを使わず音声だけを収録・処理する (既定 False = 画像と音声)。パレット「設定」の「収録: …」で切り替えられ、収録中に切り替えると次のキャプチャから効く。StartListener の \"AudioOnly\" で開始時に指定もできる。";
ListenerSetAudioOnly::usage = "ListenerSetAudioOnly[True|False] は音声のみ収録 / 画像と音声の収録を切り替える (収録中も可)。ListenerSetAudioOnly[] は切り替え (トグル)。";
VoiceQuestion::usage = "VoiceQuestion[\"質問\"] は質問を発表者の言語へ訳して音声 (SourceVault_realtime の gpt-live / gpt-realtime) で読み上げ、発表者の声の回答を書き起こして $Language (\"OutputLanguage\") へ訳したテキストセルとして出力する (非ブロック)。パレットの「🎤 Voice Q」と同じ。SourceVault のロードとパレットの「課金API: 許可」が要る。";
VoiceQuestionFinish::usage = "VoiceQuestionFinish[] は回答の聞き取りを今の時点で打ち切って出力する (パレットでは回答待ちの間ボタンが「✓ 回答を確定」になる)。";
VoiceQuestionStop::usage = "VoiceQuestionStop[] は音声質問を中止し、自分で開いた音声セッションを閉じる。";
VoiceQuestionStatus::usage = "VoiceQuestionStatus[] は音声質問の状態 (State / Status / Model / SpeakerLanguage / Spoken / Realtime) を返す。";
$VoiceQuestionModel::usage = "$VoiceQuestionModel は音声質問の声のモデル。Automatic (既定) なら SlideWorkflow の音声モデル ($SlideVoiceModel、既定 gpt-live-1)、SlideWorkflow 未ロードなら \"gpt-live-1\"。";
$VoiceQuestionSilence::usage = "$VoiceQuestionSilence は発表者が黙ってから回答を確定するまでの秒数 (既定 5)。";
$VoiceQuestionNoAnswerSeconds::usage = "$VoiceQuestionNoAnswerSeconds は何も聞こえないまま諦めるまでの秒数 (既定 40)。";
$VoiceQuestionMaxSeconds::usage = "$VoiceQuestionMaxSeconds は 1 回の回答を聞く上限秒数 (既定 180)。";
$VoiceQuestionIdleSeconds::usage = "$VoiceQuestionIdleSeconds は最後の質問から自分で開いた音声セッションを閉じるまでの秒数 (既定 120。GPT-Live は接続時間で課金)。";
$FFmpegPath::usage = "$FFmpegPath は使う ffmpeg.exe のフルパス。Automatic (既定) なら PATH → winget/scoop/choco の既知の場所の順に探す。";

If[!ValueQ[$FFmpegPath], $FFmpegPath = Automatic];
If[!ValueQ[$VoiceQuestionModel], $VoiceQuestionModel = Automatic];
If[!ValueQ[$ListenerAudioOnly], $ListenerAudioOnly = False];
If[!ValueQ[$VoiceQuestionSilence], $VoiceQuestionSilence = 5];
If[!ValueQ[$VoiceQuestionNoAnswerSeconds], $VoiceQuestionNoAnswerSeconds = 40];
If[!ValueQ[$VoiceQuestionMaxSeconds], $VoiceQuestionMaxSeconds = 180];
If[!ValueQ[$VoiceQuestionIdleSeconds], $VoiceQuestionIdleSeconds = 120];

Begin["`Private`"];

(* ============================================================ *)
(*  設定参照 & モード管理                                          *)
(* ============================================================ *)

billingAllowed[] := TrueQ[ClaudeCode`$iPaletteFallback]
$plFastMode = True;
effectiveFastMode[] := TrueQ[$plFastMode] && billingAllowed[]

(* ============================================================ *)
(*  SourceVault 融合 (仕様 §17.6 PresentationListenerCompat)        *)
(*  transcript / 解説 / 質問を SourceVault のセッション event として  *)
(*  ingest し、永続化・検索・後処理を可能にする。capture/ASR/LLM は   *)
(*  従来どおり PL 側で実行する (本融合は記録の二重化のみ)。           *)
(*  SourceVault 未ロード or 同期 OFF のときは何もしない (PL 単体動作   *)
(*  を壊さない)。                                                    *)
(* ============================================================ *)
$plSVSession = None;
$plSVSync = True;
plSVAvailableQ[] := TrueQ[$plSVSync] && StringQ[$plSVSession] &&
  Length[Names["SourceVault`SourceVaultIngestCapturedMedia"]] > 0;
plSVAppend[kind_String, text_String] := If[plSVAvailableQ[] && StringTrim[text] =!= "",
  Quiet @ Check[SourceVault`SourceVaultIngestCapturedMedia[$plSVSession, kind, text,
    "SourceRef" -> "PresentationListener", "PersistRaw" -> False], Null]];
plSVSummary[text_String] := If[plSVAvailableQ[] && StringTrim[text] =!= "",
  Quiet @ Check[SourceVault`SourceVaultUpdateLiveSummary[$plSVSession, text], Null]];
(* セッション → ノート の逆リンク: 保存した .nb のパスを session event として記録し、
   セッションからノートを辿れるようにする (PrivacyLevel 0.5 で取得可能に)。 *)
plSVLinkNotebook[path_String] := If[plSVAvailableQ[] && StringTrim[path] =!= "",
  Quiet @ Check[SourceVault`SourceVaultIngestCapturedMedia[$plSVSession, "NotebookRef", path,
    "SourceRef" -> "PresentationListener", "PersistRaw" -> False, "PrivacyLevel" -> 0.5], Null]];
ListenerSourceVaultSession[] := $plSVSession;

(* ============================================================ *)
(*  状態変数                                                      *)
(* ============================================================ *)

$recProc = None; $recStartTime = 0; $queuedSet = {};
$queue = {}; $pProc = None; $pWav = ""; $pOut = ""; $pReq = "";
$pPara = ""; $prevText = ""; $pRawText = "";
$pSt = "idle";
(* 高速: "idle"→"transcribing"→"correcting"→"commenting"→"idle"
   標準: "idle"→"transcribing"→"llmBusy"→"idle" *)

$vidDev = None; $vidDevSaved = None; $slideCount = 0; $slideBuffer = {}; $pSlides = {};
$prevFrameImg = None; $lastCapTime = None; $captureIntv = 15; $slideThresh = 0.08;
(* スライド自動クロップは既定 OFF。ON にすると「室内のスクリーン」を切り出すが、
   左側テキスト等の肝心な部分を切り落とす恐れがあるため、確信できる場合のみ。 *)
$slideAutoCrop = False; $slideMaxWidth = 1280;
$task = None; $nb = None; $transcript = ""; $buf = ""; $segs = {};
(* SourceVault 用ノート: 保存先フォルダ・保存済みパス・保存済みフラグ *)
$svNBFolder = Automatic; $nbPath = None; $nbSaved = False;
$running = False; $start = None; $errs = {}; $tmpDir = None;
$dev = None; $lang = Automatic; $outLang = Automatic; $chunkSec = 60; $minPara = 80;
$lastStartMsg = "";
$tickCount = 0; $lastTickTime = None; $lastSegCount = 0; $lastSegList = {};

(* ============================================================ *)
(*  APIキー                                                       *)
(* ============================================================ *)

(* 現行 NBAccess は NBGetAPIKey に AccessLevel >= 1.0 を要求する
   ($NBPrivacySpec の既定は 0.5 のため、無指定だとキー登録済みでも $Failed)。
   PL は明示的に AccessLevel 1.0 を渡してキーを取得する。 *)
$plKeySpec = <|"AccessLevel" -> 1.0|>;

whisperAPIKey[] := Module[{k},
  k = Quiet[NBAccess`NBGetAPIKey["openai", PrivacySpec -> $plKeySpec]];
  If[StringQ[k], k, $Failed]]

anthropicAPIKey[] := Module[{k},
  k = Quiet[NBAccess`NBGetAPIKey["anthropic", PrivacySpec -> $plKeySpec]];
  If[StringQ[k], k, $Failed]]

(* ============================================================ *)
(*  JSON I/O (ShiftJIS安全・バイナリ処理)                          *)
(*  curl直接パス用。ExportByteArray/ImportByteArray で           *)
(*  $CharacterEncoding に非依存。                                 *)
(* ============================================================ *)

plWriteJSON[file_String, data_] := Module[{ba, s},
  ba = Quiet@Check[ExportByteArray[data, "RawJSON"], None];
  If[!ByteArrayQ[ba],
    ba = Quiet@Check[StringToByteArray[ExportString[data, "RawJSON"], "UTF-8"], None]];
  If[!ByteArrayQ[ba], Return[$Failed]];
  s = OpenWrite[file, BinaryFormat -> True];
  BinaryWrite[s, Normal@ba, "Byte"]; Close[s]; file]

plReadJSON[file_String] := Module[{ba},
  If[!FileExistsQ[file] || FileByteCount[file] < 2, Return[$Failed]];
  ba = Quiet@Check[ReadByteArray[file], None];
  If[!ByteArrayQ[ba] || Length[ba] == 0, Return[$Failed]];
  (* ImportByteArray は $CharacterEncoding 非依存 *)
  Quiet@Check[ImportByteArray[ba, "RawJSON"], $Failed]]

(* Anthropic レスポンスからテキスト抽出 *)
plExtractText[json_] := Module[{content, texts},
  If[!AssociationQ[json], Return[$Failed]];
  If[KeyExistsQ[json, "error"],
    Return["[API Error: " <> ToString[Lookup[json["error"], "message", "unknown"]] <> "]"]];
  content = Lookup[json, "content", {}];
  If[!ListQ[content], Return[$Failed]];
  texts = Cases[content, a_Association /; Lookup[a, "type", ""] === "text" :> a["text"]];
  If[Length[texts] == 0, $Failed,
    StringJoin[Riffle[Select[texts, StringQ], ""]]]]

(* ============================================================ *)
(*  停止・中断                                                     *)
(* ============================================================ *)

plAbortAll[] := (
  Quiet[ClaudeCode`ClaudeAbort[]];
  If[$pProc =!= None,
    Quiet@Check[If[ProcessStatus[$pProc] === "Running", KillProcess[$pProc]], Null]];
  $pProc = None; $pSt = "idle")

(* ============================================================ *)
(*  ユーティリティ                                                  *)
(* ============================================================ *)

ts[] := DateString[{"Hour", ":", "Minute", ":", "Second"}]
elapsed[] := If[$start === None, "00:00",
  With[{s = Round@QuantityMagnitude[Now - $start, "Seconds"]},
    IntegerString[Quotient[s, 60], 10, 2] <> ":" <> IntegerString[Mod[s, 60], 10, 2]]]
nbOK[] := $nb =!= None && Quiet[Check[NBAccess`NBCellCount[$nb]; True, False], All]
wr[cell_] := If[nbOK[], (NBAccess`NBMoveToEnd[$nb]; NBAccess`NBWriteCell[$nb, cell])]

readUTF8Text[file_String] := Module[{bytes},
  If[!FileExistsQ[file] || FileByteCount[file] < 1, Return[""]];
  bytes = Quiet@Check[ReadByteArray[file], None];
  If[bytes === None || Length[bytes] == 0, Return[""]];
  If[Length[bytes] >= 3 && bytes[[1]] == 239 && bytes[[2]] == 187 && bytes[[3]] == 191,
    bytes = bytes[[4 ;;]]];
  Quiet@Check[ByteArrayToString[bytes, "UTF-8"], ""]]

extractTitle[commentary_String] := Module[{lines, first},
  lines = Select[StringSplit[commentary, "\n"], StringLength[StringTrim[#]] > 0 &];
  If[Length[lines] == 0, Return["---"]];
  first = StringTrim[lines[[1]]];
  first = StringReplace[first, {StartOfString ~~ "TITLE:" ~~ Whitespace... -> "",
    StartOfString ~~ "タイトル:" ~~ Whitespace... -> "",
    StartOfString ~~ "タイトル：" ~~ Whitespace... -> ""}, IgnoreCase -> True];
  first = StringReplace[first, {StartOfLine ~~ "#" .. ~~ " " -> "",
    "**" -> "", "「" -> "", "」" -> "", "\"" -> ""}];
  first = StringTrim[first];
  (* 英語など ASCII のタイトルは 1 文字あたりの情報量が少ないので長めに残す *)
  If[PrintableASCIIQ[first],
    If[StringLength[first] > 60,
      first = StringTake[first, 60];
      (* 単語の途中で切らない *)
      first = StringTrim[StringReplace[first, RegularExpression["\\s+\\S*$"] -> ""]]],
    If[StringLength[first] > 35, first = StringTake[first, 35]]];
  If[StringLength[first] < 2, "---", first]]

stripTitle[commentary_String] := Module[{lines},
  lines = StringSplit[commentary, "\n"];
  If[Length[lines] <= 1, Return[commentary]];
  StringTrim[StringJoin[Riffle[Rest[lines], "\n"]]]]

(* ============================================================ *)
(*  プロンプト                                                     *)
(* ============================================================ *)

$sysP = "あなたは理論計算機科学・数理科学に精通した研究者です。\
プレゼンテーションの書き起こしテキストを読み、以下を行ってください：\n\
1. 話者が述べている核心的な主張・定理・概念を正確に特定し、簡潔にまとめる\n\
2. その主張の学術的意義や、関連する先行研究・理論との関係を補足する\n\
3. 専門用語があれば、その正確な定義や背景を補足する\n\
4. 話者の議論の論理的流れを明確にする\n\n\
【出力形式】\n\
1行目：短いタイトル（簡潔な名詞句。日本語なら10〜25文字）\n\
2行目：空行\n\
3行目以降：解説本文（5〜8文程度）\n\n\
内容の本質を捉えた深い解説を心がけてください。";

$sysPV = "あなたは理論計算機科学・数理科学に精通した研究者です。\
プレゼンテーションの書き起こしテキストと、スライド画像が与えられます。\n\
以下を行ってください：\n\
1. スライドの図表・数式と話者の発言を統合し、核心的な主張を特定する\n\
2. スライドに含まれる図や数式の意味を解説する\n\
3. 学術的意義や先行研究との関係を補足する\n\
4. 専門用語の定義や背景を補足する\n\n\
【出力形式】\n\
1行目：短いタイトル（簡潔な名詞句。日本語なら10〜25文字）\n\
2行目：空行\n\
3行目以降：解説本文（5〜8文程度）";

(* 書き起こしの言語は変えない (翻訳は解説生成時に行う)。旧版は「日本語テキスト」
   前提だったため、英語などの発表では修正拒否や勝手な翻訳が起きていた。 *)
$correctP = "音声認識の後処理ツールとして、以下の書き起こしテキストの明らかな誤りを修正してください。\n\n\
ルール: テキストの言語はそのまま保つ（翻訳しない）、同音異義語・聞き誤りの修正、明らかな誤字修正、\
文構造・語順を変えない、句読点を変えない、修正不要ならそのまま返す、修正済みテキストのみ出力。";

(* ============================================================ *)
(*  出力言語 ($Language) と発表言語 (Whisper)                       *)
(*  発表言語: "Language" (Automatic = Whisper 自動判定)             *)
(*  出力言語: "OutputLanguage" (Automatic = $Language)              *)
(*  タイトル・解説・Q&A は出力言語で書き、発言が別言語なら          *)
(*  $plTrMarker 行の後に発言の訳を付けさせる (追加 API 呼び出しなし)。 *)
(* ============================================================ *)

$plTrMarker = "@@TRANSLATION@@";

plOutLang[] := If[StringQ[$outLang] && StringTrim[$outLang] =!= "", $outLang,
  If[StringQ[$Language], $Language, "Japanese"]]

plLangName[l_String] := Switch[l,
  "Japanese", "Japanese (日本語)",
  "ChineseSimplified", "Simplified Chinese (简体中文)",
  "ChineseTraditional", "Traditional Chinese (繁體中文)",
  "Korean", "Korean (한국어)",
  _, l]
plLangName[_] := plLangName["Japanese"]

(* Whisper の language パラメータ (ISO-639-1)。Automatic/不明なら None = 自動判定 *)
$plWhisperCodes = <|"Japanese" -> "ja", "English" -> "en", "French" -> "fr",
  "German" -> "de", "Spanish" -> "es", "Italian" -> "it", "Portuguese" -> "pt",
  "Russian" -> "ru", "Korean" -> "ko", "Chinese" -> "zh", "ChineseSimplified" -> "zh",
  "ChineseTraditional" -> "zh", "Dutch" -> "nl", "Polish" -> "pl", "Turkish" -> "tr",
  "Arabic" -> "ar", "Hindi" -> "hi", "Indonesian" -> "id", "Vietnamese" -> "vi",
  "Thai" -> "th", "Swedish" -> "sv", "Ukrainian" -> "uk", "Czech" -> "cs"|>;
plWhisperLang[l_String] := Which[
  KeyExistsQ[$plWhisperCodes, l], $plWhisperCodes[l],
  StringMatchQ[l, RegularExpression["[a-z]{2,3}"]], l,
  True, None]
plWhisperLang[_] := None
plWhisperLangArgs[l_] := With[{c = plWhisperLang[l]},
  If[StringQ[c], {"-F", "language=" <> c}, {}]]

(* 解説系プロンプトに付ける出力言語の指示 *)
plLangInstr[] := With[{L = plLangName[plOutLang[]]},
  "\n\n【出力言語】\nタイトルと解説本文は必ず " <> L <>
  " で書いてください（書き起こしやスライドが別の言語でも " <> L <> " で書く）。\n" <>
  "最新の書き起こしの主な言語が " <> L <> " でない場合に限り、解説本文の後に " <>
  $plTrMarker <> " とだけ書いた行を置き、その後に最新の書き起こしの忠実な " <> L <>
  " 訳を出力してください（要約せず全文を訳す）。書き起こしが " <> L <>
  " の場合は、この行も訳も出力しないでください。"]

plSysPrompt[vision_] := If[TrueQ[vision], $sysPV, $sysP] <> plLangInstr[]

(* LLM 応答を {解説, 訳} に分ける。マーカーがなければ訳は "" *)
splitTranslation[c_String] := Module[{pos, main, tr},
  pos = StringPosition[c, $plTrMarker, 1];
  If[pos === {}, Return[{StringTrim[c], ""}]];
  main = StringTake[c, pos[[1, 1]] - 1];
  tr = StringDrop[c, pos[[1, 2]]];
  (* マーカー行の装飾 (太字記号・見出し記号・区切り線) の取り残しを除く *)
  main = StringTrim[StringReplace[StringTrim[main],
    RegularExpression["(\\n[ \\t*#`-]*)+$"] -> ""]];
  tr = StringTrim[StringReplace[tr, RegularExpression["^[*`]+"] -> ""]];
  {main, tr}]
splitTranslation[other_] := {other, ""}

$processCellsP = "あなたは理論計算機科学に精通した研究アシスタントです。\
ノートブックのセル内容が与えられます。ユーザーのプロンプトに従って処理してください。\n\
ルール: Mathematicaコードは ```mathematica で囲む、テキストは日本語、数式はMathematica形式。";

(* ============================================================ *)
(*  ノイズフィルタ                                                  *)
(* ============================================================ *)

noiseQ[t_String] := StringLength[t] < 4 ||
  StringMatchQ[t, ("ご視聴" | "ご覧" | "お疲れ" | "ありがとう" | "字幕" |
    "Thanks" | "Thank you" | "Bye" | "See you" | "MBS" | "BS" | "TV" |
    "おやすみ" | "本日はご覧" | "チャンネル登録") ~~ ___]

refusalQ[t_String] := StringContainsQ[t,
  "申し訳" | "お応えできません" | "リクエスト" | "I can't" | "I cannot" |
  "I'm sorry" | "not in Japanese" | "corrupted" | "Please provide" | "I apologize"]

(* ============================================================ *)
(*  ビデオキャプチャ & スライド検出                                   *)
(* ============================================================ *)

listDshowDevices[] := Module[{r, stderr, lines, audio = {}, video = {}, i, name, alt, target},
  If[!ffmpegAvailableQ[], Return[<|"audio" -> {}, "video" -> {}|>]];
  r = Quiet@RunProcess[{ffmpegExe[], "-list_devices", "true", "-f", "dshow", "-i", "dummy"}];
  If[!AssociationQ[r], Return[<|"audio" -> {}, "video" -> {}|>]];
  stderr = r["StandardError"];
  If[!StringQ[stderr], Return[<|"audio" -> {}, "video" -> {}|>]];
  (* ffmpeg は UTF-8 で書くが RunProcess は 1 バイト 1 文字で返す (「マイク」が化ける) *)
  If[Max[ToCharacterCode[stderr], 0] < 256,
    stderr = Quiet@Check[FromCharacterCode[ToCharacterCode[stderr], "UTF-8"], stderr]];
  lines = StringSplit[stderr, "\n"];
  Do[If[StringContainsQ[lines[[i]], "(audio)"] || StringContainsQ[lines[[i]], "(video)"],
      target = If[StringContainsQ[lines[[i]], "(audio)"], "audio", "video"];
      name = First[StringCases[lines[[i]], "\"" ~~ n__ ~~ "\"" :> n], None];
      alt = None;
      If[i < Length[lines] && StringContainsQ[lines[[i + 1]], "Alternative name"],
        alt = First[StringCases[lines[[i + 1]], "\"" ~~ a__ ~~ "\"" :> a], None]];
      If[name =!= None,
        If[target === "audio", AppendTo[audio, <|"name" -> name, "alt" -> alt|>],
          AppendTo[video, <|"name" -> name, "alt" -> alt|>]]]],
    {i, Length[lines]}];
  <|"audio" -> audio, "video" -> video|>]

(* ffmpeg の実行ファイルを解決する。PATH だけに頼ると、winget 等で入れた直後は
   起動済みの Mathematica が新しい PATH を知らないため「見つからない」になる。
   $FFmpegPath (明示) → PATH → 既知のインストール先 の順に探し、見つけたものだけ
   キャッシュする (見つからない結果は 10 秒ごとに探し直す = 入れた後に再起動不要)。 *)
ffmpegCandidates[] := Module[{la = Environment["LOCALAPPDATA"], up = $HomeDirectory, pkgs},
  pkgs = If[StringQ[la],
    Quiet@FileNames["ffmpeg.exe",
      FileNames["*FFmpeg*", FileNameJoin[{la, "Microsoft", "WinGet", "Packages"}]], Infinity], {}];
  Join[{"ffmpeg"},
    If[StringQ[la], {FileNameJoin[{la, "Microsoft", "WinGet", "Links", "ffmpeg.exe"}]}, {}],
    If[ListQ[pkgs], pkgs, {}],
    {FileNameJoin[{up, "scoop", "shims", "ffmpeg.exe"}],
     "C:\\ProgramData\\chocolatey\\bin\\ffmpeg.exe",
     "C:\\Program Files\\ffmpeg\\bin\\ffmpeg.exe",
     "C:\\ffmpeg\\bin\\ffmpeg.exe"}]]

ffmpegRunsQ[exe_String] := (exe === "ffmpeg" || FileExistsQ[exe]) &&
  IntegerQ[Quiet@Check[RunProcess[{exe, "-hide_banner", "-version"}, "ExitCode"], $Failed]]

$ffmpegExe = None; $ffmpegProbeTime = -Infinity; $ffmpegProbedFor = Automatic;
ffmpegExe[] := Module[{c},
  (* $FFmpegPath を変えたら待たずに探し直す *)
  If[$FFmpegPath =!= $ffmpegProbedFor,
    $ffmpegExe = None; $ffmpegProbeTime = -Infinity; $ffmpegProbedFor = $FFmpegPath];
  If[$ffmpegExe === None && AbsoluteTime[] - $ffmpegProbeTime > 10,
    $ffmpegProbeTime = AbsoluteTime[];
    c = If[StringQ[$FFmpegPath], {$FFmpegPath}, ffmpegCandidates[]];
    $ffmpegExe = SelectFirst[c, ffmpegRunsQ, None]];
  If[StringQ[$ffmpegExe], $ffmpegExe, "ffmpeg"]]
ffmpegAvailableQ[] := (ffmpegExe[]; StringQ[$ffmpegExe])
$ffmpegMissingMsg = "ffmpeg が見つかりません。winget install Gyan.FFmpeg で入れるか、PresentationListener`$FFmpegPath に ffmpeg.exe のパスを設定してください。";

$deviceCache = None; $deviceCacheTime = 0;
getDevices[] := (If[$deviceCache === None || (AbsoluteTime[] - $deviceCacheTime) > 30,
    $deviceCache = listDshowDevices[]; $deviceCacheTime = AbsoluteTime[]]; $deviceCache)
refreshDevices[] := ($deviceCache = None; getDevices[])
ListAudioDevices[] := getDevices[]["audio"]
ListVideoDevices[] := getDevices[]["video"]

getDefaultAudioDevice[] := Module[{r, name, devs, match, asciiParts},
  r = Quiet@RunProcess[{"powershell", "-Command",
    "Get-CimInstance Win32_SoundDevice | Where-Object {$_.StatusInfo -eq 3} | Select-Object -First 1 -ExpandProperty Name"},
    "StandardOutput"];
  If[!StringQ[r] || StringLength[StringTrim[r]] == 0,
    r = Quiet@RunProcess[{"powershell", "-Command", "(Get-AudioDevice -Recording).Name"}, "StandardOutput"]];
  name = If[StringQ[r], StringTrim[r], ""];
  devs = ListAudioDevices[]; If[Length[devs] == 0, Return[None]];
  If[StringLength[name] > 0,
    asciiParts = StringCases[name, RegularExpression["[A-Za-z0-9][A-Za-z0-9 ._-]{2,}"]];
    match = Select[devs, Function[dev,
      AnyTrue[asciiParts, StringContainsQ[dev["name"], #, IgnoreCase -> True] &] ||
      (StringQ[dev["alt"]] && AnyTrue[asciiParts, StringContainsQ[dev["alt"], #, IgnoreCase -> True] &])]];
    If[Length[match] > 0, Return[match[[1]]]]]; devs[[1]]]

deviceId[dev_Association] := If[StringQ[dev["alt"]], dev["alt"], dev["name"]]
deviceId[None] := None; deviceId[s_String] := s

captureFrame[] := Module[{f},
  If[$vidDev === None, Return[None]];
  f = FileNameJoin[{$tmpDir, "frame_" <> ToString[$slideCount] <> ".jpg"}];
  Quiet@Check[RunProcess[{ffmpegExe[], "-y", "-f", "dshow", "-rtbufsize", "100M",
    "-i", "video=" <> $vidDev, "-frames:v", "1", "-update", "1", "-q:v", "2", f}, "ExitCode"], 1];
  If[FileExistsQ[f] && FileByteCount[f] > 1000, $slideCount++; f, None]]

(* フレーム全体を $slideMaxWidth 幅に縮小 (アスペクト保持・拡大はしない)。
   旧実装は 800px 固定だったが、左側の細かいテキストが LLM で読めるよう既定を広げる。 *)
resizeSlide[img_Image] := ImageResize[img, {Min[$slideMaxWidth, First@ImageDimensions[img]]}]
resizeSlide[other_] := other

(* スライド検出。既定 ($slideAutoCrop=False) ではクロップせずフレーム全体を返す。
   旧実装は「最も明るい連結成分 (5〜70%)」へ無条件にクロップしていたため、
   明るい図 (例: 宇宙の画像) が選ばれ、暗背景の左テキストなど肝心な部分が
   切り落とされていた。クロップは確信できる場合のみ ($slideAutoCrop=True) 行う。 *)
detectSlide[imgFile_String] := Module[{img},
  img = Quiet@Import[imgFile]; If[!ImageQ[img], Return[None]];
  If[!TrueQ[$slideAutoCrop], Return[resizeSlide[img]]];
  detectSlideCrop[img]]

(* 保守的なクロップ: 検出領域が (1) フレームの 40〜85%、(2) アスペクト比 1.1〜2.4、
   (3) 周囲より十分明るい (室内スクリーン的) — を全て満たすときだけ切り出す。
   いずれか外れれば全体を残す。ImageTrim の padding は正値にして縁を切らない。 *)
detectSlideCrop[img_Image] := Module[{gray, bin, comps, measures, largest, bbox,
    dims, frameArea, bw, bh, regionArea, aspect, regionMean, overallMean, cropped},
  dims = ImageDimensions[img]; frameArea = Times @@ dims;
  gray = ColorConvert[img, "Grayscale"];
  bin = Closing[Opening[Binarize[gray, 0.35], DiskMatrix[5]], DiskMatrix[10]];
  comps = MorphologicalComponents[bin];
  If[Max[comps] == 0, Return[resizeSlide[img]]];
  measures = ComponentMeasurements[comps, {"Area", "BoundingBox"}, #Area > frameArea * 0.2 &];
  If[Length[measures] == 0, Return[resizeSlide[img]]];
  largest = First@MaximalBy[measures, #[[2, 1]] &]; bbox = largest[[2, 2]];
  bw = bbox[[2, 1]] - bbox[[1, 1]]; bh = bbox[[2, 2]] - bbox[[1, 2]];
  regionArea = bw * bh; aspect = If[bh > 0, bw/bh, 0];
  If[regionArea > frameArea * 0.85 || regionArea < frameArea * 0.4 ||
     aspect < 1.1 || aspect > 2.4, Return[resizeSlide[img]]];
  regionMean = Quiet@Check[ImageMeasurements[ImageTrim[gray, bbox], "Mean"], 1];
  overallMean = Quiet@Check[ImageMeasurements[gray, "Mean"], 0];
  If[!NumericQ[regionMean] || !NumericQ[overallMean] ||
     regionMean < overallMean + 0.15, Return[resizeSlide[img]]];
  cropped = Quiet@Check[ImageTrim[img, bbox, 12], img];
  resizeSlide[cropped]]

slideChangedQ[new_Image, prev_Image] := ImageDistance[ImageResize[new, {200}], ImageResize[prev, {200}]] > $slideThresh
slideChangedQ[_, _] := True

imageToBase64[img_Image] := Module[{f, bytes},
  f = FileNameJoin[{$tmpDir, "slide_b64_" <> ToString[$slideCount] <> ".jpg"}];
  Export[f, img, "JPEG", ImageResolution -> 150];
  bytes = ReadByteArray[f]; Quiet@DeleteFile[f]; BaseEncode[bytes]]
imageToBase64[_] := None

tickVideo[] := Module[{now, frameFile, slide, b64},
  If[$vidDev === None, Return[]]; now = AbsoluteTime[];
  If[$lastCapTime =!= None && (now - $lastCapTime) < $captureIntv, Return[]];
  $lastCapTime = now; frameFile = captureFrame[];
  If[frameFile === None, Return[]]; slide = detectSlide[frameFile];
  If[!ImageQ[slide], Return[]];
  If[slideChangedQ[slide, $prevFrameImg],
    b64 = imageToBase64[slide];
    If[StringQ[b64], AppendTo[$slideBuffer, <|"img" -> slide, "b64" -> b64, "time" -> elapsed[]|>]];
    $prevFrameImg = slide]]

CaptureNow[] := Module[{frameFile, slide, b64, msg},
  If[!$running, Return["Not running."]];
  If[$vidDev === None, Return[If[TrueQ[$ListenerAudioOnly],
    "音声のみ収録中です (パレットの「収録」で画像+音声に切り替え)。", "No video device."]]];
  frameFile = captureFrame[]; If[frameFile === None, Return["Capture failed."]];
  slide = detectSlide[frameFile]; If[!ImageQ[slide], Return["Failed."]];
  b64 = imageToBase64[slide]; If[!StringQ[b64], Return["Base64 failed."]];
  AppendTo[$slideBuffer, <|"img" -> slide, "b64" -> b64, "time" -> elapsed[]|>];
  $prevFrameImg = slide; $lastCapTime = AbsoluteTime[];
  msg = "Capture [" <> elapsed[] <> "] " <> ToString[Length[$slideBuffer]] <> " slides";
  If[nbOK[], wr[Cell[TextData[{StyleBox[msg, FontSlant -> "Italic"]}], "Text"]];
    wr[Cell[BoxData[ToBoxes[Show[slide, ImageSize -> 400]]], "Output",
      CellMargins -> {{30, 20}, {3, 3}}]];
    plPersistNotebook[]]; "Captured."]

TestVideo[d_String] := Module[{f, ec, img, slide},
  f = FileNameJoin[{$TemporaryDirectory, "pa_vtest.jpg"}];
  ec = RunProcess[{ffmpegExe[], "-y", "-f", "dshow", "-rtbufsize", "100M",
    "-i", "video=" <> d, "-frames:v", "1", "-update", "1", "-q:v", "2", f}, "ExitCode"];
  If[!FileExistsQ[f] || FileByteCount[f] < 1000, Return[$Failed]];
  img = Import[f]; slide = detectSlide[f]; Quiet@DeleteFile[f]; {img, slide}]

(* ============================================================ *)
(*  SourceVault ノート保存                                          *)
(*  新規ノートは SourceVaultNewNotebook[] (テンプレ由来) で開く。     *)
(*  タイトルが読み取れた時点で 既定 SourceVault ノートフォルダへ      *)
(*    yyyymmdd-<タイトル>-presentation.nb                           *)
(*  として保存し、SourceVaultRegisterNotebook で参照登録する。       *)
(*  以後 plPersistNotebook[] で発言/解説/画像をファイルへ反映する。   *)
(* ============================================================ *)

(* 既定 SourceVault ノートブックフォルダを解決する。
   優先: StartListener "NotebookFolder" ($svNBFolder)
        → SourceVault`$SourceVaultDefaultNotebookFolder
        → Global`$onWork → Global`$packageDirectory *)
plResolveNBFolder[] := Module[{f},
  f = $svNBFolder;
  If[StringQ[f] && DirectoryQ[f], Return[f]];
  f = Quiet @ Symbol["SourceVault`$SourceVaultDefaultNotebookFolder"];
  If[StringQ[f] && DirectoryQ[f], Return[f]];
  f = Quiet @ Symbol["Global`$onWork"];
  If[StringQ[f] && DirectoryQ[f], Return[f]];
  f = Quiet @ Symbol["Global`$packageDirectory"];
  If[StringQ[f] && DirectoryQ[f], Return[f]];
  None]

(* タイトルを Windows でも安全なファイル名要素に整える *)
plSanitizeName[title_String] := Module[{s},
  s = StringReplace[title, {
    ("/" | "\\" | ":" | "*" | "?" | "\"" | "<" | ">" | "|") -> "_",
    ("\n" | "\r" | "\t") -> " "}];
  s = StringReplace[s, Repeated[" "] -> " "];
  s = StringTrim[s];
  If[StringLength[s] > 40, s = StringTrim[StringTake[s, 40]]];
  If[s === "", s = "presentation"]; s]

plNBFileName[title_String] := Module[{safe, date},
  date = DateString[{"Year", "Month", "Day"}];   (* yyyymmdd *)
  safe = plSanitizeName[title];
  If[safe === "presentation",
    date <> "-presentation.nb",
    date <> "-" <> safe <> "-presentation.nb"]]

(* 既存ファイルは上書きしない。重複時は連番を付ける。 *)
plUniquePath[folder_String, fname_String] := Module[{base, ext, path, i},
  base = FileBaseName[fname]; ext = FileExtension[fname];
  path = FileNameJoin[{folder, fname}]; i = 1;
  While[FileExistsQ[path],
    path = FileNameJoin[{folder, base <> "-" <> IntegerString[i, 10, 2] <> "." <> ext}];
    i++];
  path]

(* タイトルが読み取れた時点で 1 度だけ保存し、SourceVault に登録する。 *)
plSaveNotebook[title_String] := Module[{folder, fname, path},
  If[$nbSaved || !nbOK[], Return[$nbSaved]];
  folder = plResolveNBFolder[];
  If[!StringQ[folder],
    wr[Cell["保存先フォルダを解決できませんでした ($onWork / $packageDirectory を確認)",
      "Text", FontColor -> RGBColor[0.7, 0.3, 0.1], FontSize -> 10]];
    Return[False]];
  fname = plNBFileName[title];
  path = plUniquePath[folder, fname];
  If[Quiet@Check[NotebookSave[$nb, path]; True, False] =!= True, Return[False]];
  $nbPath = path; $nbSaved = True;
  (* SourceVault がこのノートを参照できるよう登録 (best effort) *)
  If[Length[Names["SourceVault`SourceVaultRegisterNotebook"]] > 0,
    Quiet @ Check[SourceVault`SourceVaultRegisterNotebook[path], Null]];
  (* 双方向リンク: セッション側にもノートのパスを記録する *)
  plSVLinkNotebook[path];
  wr[Cell[TextData[{
    StyleBox["保存: ", FontWeight -> Bold, FontColor -> GrayLevel[0.5], FontSize -> 10],
    StyleBox[path, FontColor -> GrayLevel[0.5], FontSize -> 10]}], "Text"]];
  True]

(* 保存済みなら 現在の内容 (画像含む) をファイルへ反映する。 *)
plPersistNotebook[] := If[$nbSaved && nbOK[],
  Quiet @ Check[NotebookSave[$nb], Null]]

(* 保存済みノートを SourceVault に即時 index 化し、snapshot/SymbolicPath を永続化する。
   (別 PC 検索・要約キャッシュの確実性のため。Find は遅延 index するが、ここで先に確定させる。) *)
plIndexNotebook[] := If[$nbSaved && StringQ[$nbPath] && FileExistsQ[$nbPath] &&
    Length[Names["SourceVault`SourceVaultIndexNotebook"]] > 0,
  Quiet @ Check[SourceVault`SourceVaultIndexNotebook[$nbPath], Null]]

(* ============================================================ *)
(*  ノートブック & 診断                                            *)
(* ============================================================ *)

(* 新規ノートは SourceVault テンプレート由来の未保存ウィンドウとして開く。
   SourceVault 未ロード時は従来どおり CreateDocument にフォールバックする。 *)
makeNB[] := Module[{res, nbObj},
  res = If[Length[Names["SourceVault`SourceVaultNewNotebook"]] > 0,
    Quiet @ Check[SourceVault`SourceVaultNewNotebook[
      "Title" -> "Presentation", "Keywords" -> {"presentation"},
      "SessionID" -> $plSVSession], $Failed],
    $Failed];
  nbObj = If[AssociationQ[res] && Lookup[res, "Status", ""] === "OK",
    Lookup[res, "Notebook", None], None];
  $nb = If[Head[nbObj] === NotebookObject,
    nbObj,
    CreateDocument[{
      Cell["Presentation Listener", "Title"],
      Cell["StopListener[] / AskQuestion[\"...\"]", "Text", FontColor -> GrayLevel[0.5], FontSize -> 11],
      Cell["", "Text"]
    }, WindowTitle -> "Presentation Listener", WindowSize -> {700, 800}, Saveable -> True]];
  $nb]

TestMic[sec_Integer: 5, d_String: ""] := Module[{f, r, a},
  If[d === "", Return[$Failed]];
  f = FileNameJoin[{$TemporaryDirectory, "pa_test.wav"}];
  r = RunProcess[{ffmpegExe[], "-y", "-f", "dshow", "-i", "audio=" <> d,
    "-t", ToString[sec], "-ar", "16000", "-ac", "1", "-acodec", "pcm_s16le", f}, "ExitCode"];
  If[r =!= 0, Return[$Failed]];
  a = Quiet@Import[f, "Audio"];
  If[AudioQ[a], Print["OK MaxAmp=", Max@Abs@AudioData[a]]; f, $Failed]]

TestWhisper[w_String, lang_: "ja"] := Module[{k, o, ec, t},
  k = whisperAPIKey[]; If[k === $Failed, Return[$Failed]];
  o = w <> ".txt";
  ec = RunProcess[Join[{"curl", "-s", "-o", o, "https://api.openai.com/v1/audio/transcriptions",
    "-H", "Authorization: Bearer " <> k, "-F", "file=@" <> w,
    "-F", "model=whisper-1"}, plWhisperLangArgs[lang], {"-F", "response_format=text"}], "ExitCode"];
  t = If[ec === 0, readUTF8Text[o], $Failed]; Quiet@DeleteFile[o]; t]

DiagState[] := Column[{
  "running: " <> ToString[$running], "state: " <> $pSt,
  "mode: " <> If[effectiveFastMode[], "⚡高速 (curl直接)", "🔧標準 (CLI優先)"],
  "billingAPI: " <> If[billingAllowed[], "許可", "禁止"],
  "tickCount: " <> ToString[$tickCount] <>
    "  lastTick: " <> If[$lastTickTime === None, "never",
      ToString[Round@QuantityMagnitude[Now - $lastTickTime, "Seconds"]] <> "s ago"],
  "task alive: " <> ToString[$task =!= None && MemberQ[ScheduledTasks[], $task]],
  "recProc: " <> ToString[If[$recProc =!= None, ProcessStatus[$recProc], "None"]],
  "segFiles: " <> ToString[$lastSegCount] <> " " <> ToString[$lastSegList],
  "pProc: " <> ToString[If[$pProc =!= None, ProcessStatus[$pProc], "None"]],
  "queue: " <> ToString[Length[$queue]],
  "lang: " <> ToString[Replace[plWhisperLang[$lang], None -> "auto"]] <>
    " → output: " <> plOutLang[],
  "dev: " <> ToString[$dev], "vidDev: " <> ToString[$vidDev],
  "slides: " <> ToString[Length[$slideBuffer]],
  "buf: " <> ToString[StringLength[$buf]] <> "c",
  "transcript: " <> ToString[StringLength[$transcript]] <> "c",
  "errors: " <> If[Length[$errs] > 0,
    StringRiffle[ToString[#["msg"]] & /@ Take[$errs, UpTo[3]], "; "], "(none)"]}]

(* ============================================================ *)
(*  連続録音 & tick                                                *)
(* ============================================================ *)

startContinuousRecording[] := (
  $recProc = Quiet@Check[StartProcess[{ffmpegExe[], "-y",
    "-f", "dshow", "-rtbufsize", "100M", "-i", "audio=" <> $dev,
    "-ar", "16000", "-ac", "1", "-acodec", "pcm_s16le",
    "-f", "segment", "-segment_time", ToString[$chunkSec], "-segment_format", "wav",
    "-reset_timestamps", "1", FileNameJoin[{$tmpDir, "seg_%03d.wav"}]}], None];
  $recStartTime = AbsoluteTime[])

tick[] := If[!$running, Null,
  $tickCount++; $lastTickTime = Now;
  Check[(tickRec[]; tickVideo[]; tickProc[]),
    AppendTo[$errs, <|"time" -> Now, "msg" -> ToString[$MessageList]|>]]]

tickRec[] := Module[{files, ready, stderr},
  If[$recProc === None || ProcessStatus[$recProc] =!= "Running",
    If[$recProc =!= None && ProcessStatus[$recProc] === "Finished",
      stderr = Quiet@Check[ReadString[ProcessConnection[$recProc, "StandardError"]], ""];
      If[StringQ[stderr] && StringLength[stderr] > 0,
        AppendTo[$errs, <|"time" -> Now, "msg" -> StringTake[stderr, -Min[500, StringLength[stderr]]]|>]]];
    If[NumberQ[$recStartTime] && (AbsoluteTime[] - $recStartTime) < 5, Return[]];
    If[$running, startContinuousRecording[]]; Return[]];
  files = Sort@Quiet@FileNames["seg_*.wav", $tmpDir];
  $lastSegCount = Length[files];
  $lastSegList = FileNameTake /@ files;
  If[Length[files] < 2, Return[]];
  ready = Select[Most[files], !MemberQ[$queuedSet, #] &];
  If[Length[ready] > 0, $queue = Join[$queue, ready]; $queuedSet = Join[$queuedSet, ready]]]

(* ============================================================ *)
(*  tickProc: ⚡高速モード / 🔧標準モード 統合ステートマシン         *)
(* ============================================================ *)

tickProc[] := Switch[$pSt,

  (* === 共通: Whisper 開始 === *)
  "idle",
    If[Length[$queue] > 0,
      $pWav = First[$queue]; $queue = Rest[$queue];
      If[!FileExistsQ[$pWav] || FileByteCount[$pWav] < 5000, Return[]];
      Module[{k = whisperAPIKey[], args},
        If[k === $Failed, Return[]];
        $pOut = $pWav <> ".txt";
        (* 発表言語が Automatic なら language を付けず Whisper に自動判定させる *)
        args = Join[{"curl", "-s", "-o", $pOut, "https://api.openai.com/v1/audio/transcriptions",
          "-H", "Authorization: Bearer " <> k,
          "-F", "file=@" <> $pWav, "-F", "model=whisper-1"},
          plWhisperLangArgs[$lang], {"-F", "response_format=text"}];
        If[StringLength[$prevText] > 0, args = Join[args, {"-F", "prompt=" <> $prevText}]];
        $pProc = Quiet@Check[StartProcess[args], None];
        If[$pProc =!= None, $pSt = "transcribing"]]],

  (* === 共通: Whisper 完了 → 分岐 === *)
  "transcribing",
    If[$pProc === None || ProcessStatus[$pProc] =!= "Running",
      Module[{text},
        text = StringTrim[readUTF8Text[$pOut]]; Quiet@DeleteFile[$pOut];
        If[text === "" || noiseQ[text], $pSt = "idle"; Return[]];
        $pRawText = text;
        If[effectiveFastMode[],
          (* ⚡ 高速: curl で ASR修正 開始 *)
          startFastCorrection[text],
          (* 🔧 標準: ClaudeQueryAsync *)
          startStandardCorrection[text]]]],

  (* === ⚡高速: ASR修正 curl ポーリング === *)
  "correcting",
    If[$pProc === None || ProcessStatus[$pProc] =!= "Running",
      Module[{body, corrected},
        body = plReadJSON[$pOut];
        Quiet@DeleteFile[$pOut]; Quiet@DeleteFile[$pReq];
        corrected = plExtractText[body];
        If[!StringQ[corrected] || StringLength[StringTrim[corrected]] == 0,
          corrected = $pRawText];
        If[refusalQ[corrected], corrected = $pRawText];
        corrected = StringTrim[corrected];
        $prevText = StringTake[corrected, -Min[StringLength[corrected], 200]];
        $buf = If[$buf === "", corrected, $buf <> " " <> corrected];
        $transcript = $transcript <> corrected <> "\n";
        If[StringLength[$buf] >= $minPara,
          startFastCommentary[$buf]; $buf = "",
          $pSt = "idle"]]],

  (* === ⚡高速: 解説生成 curl ポーリング === *)
  "commenting",
    If[$pProc === None || ProcessStatus[$pProc] =!= "Running",
      Module[{body, commentary},
        body = plReadJSON[$pOut];
        Quiet@DeleteFile[$pOut]; Quiet@DeleteFile[$pReq];
        commentary = plExtractText[body];
        If[!StringQ[commentary] || StringLength[StringTrim[commentary]] == 0,
          commentary = "[応答取得失敗]"];
        writeCommentarySection[$pPara, commentary, $pSlides];
        $pSt = "idle"]],

  (* === 🔧標準: ClaudeQueryAsync コールバック待ち === *)
  "llmBusy", Null,

  _, Null
]

(* ============================================================ *)
(*  ⚡高速パス: curl で Anthropic API 直接呼び出し                  *)
(*  v15と同じ: StartProcess[curl] → tickでポーリング               *)
(*  PowerShell/iStartFallbackAsync 不使用 → 起動コスト0           *)
(* ============================================================ *)

startFastCorrection[text_String] := Module[{k, reqF},
  k = anthropicAPIKey[];
  If[k === $Failed, (* APIキーなし: 修正スキップ *)
    $prevText = StringTake[text, -Min[StringLength[text], 200]];
    $buf = If[$buf === "", text, $buf <> " " <> text];
    $transcript = $transcript <> text <> "\n";
    If[StringLength[$buf] >= $minPara,
      startFastCommentary[$buf]; $buf = "",
      $pSt = "idle"];
    Return[]];
  reqF = FileNameJoin[{$tmpDir, "corr_req.json"}];
  $pOut = FileNameJoin[{$tmpDir, "corr_resp.json"}];
  $pReq = reqF;
  plWriteJSON[reqF, <|
    "model" -> "claude-sonnet-4-6",
    "max_tokens" -> 2048,
    "messages" -> {
      <|"role" -> "user", "content" -> $correctP <> "\n\n" <> text|>}|>];
  $pProc = Quiet@Check[StartProcess[{
    "curl", "-s", "--max-time", "60",
    "-o", $pOut, "-X", "POST",
    "https://api.anthropic.com/v1/messages",
    "-H", "Content-Type: application/json; charset=utf-8",
    "-H", "x-api-key: " <> k,
    "-H", "anthropic-version: 2023-06-01",
    "--data-binary", "@" <> reqF}], None];
  If[$pProc =!= None, $pSt = "correcting", $pSt = "idle"]
]

startFastCommentary[para_String] := Module[{k, ctx, prompt, userContent,
    sysPrompt, imgParts, reqF},
  k = anthropicAPIKey[];
  If[k === $Failed, $pSt = "idle"; Return[]];
  $pPara = para;
  $pSlides = $slideBuffer; $slideBuffer = {};

  ctx = If[Length[$segs] > 0,
    "これまでの内容：\n" <> StringRiffle[#["text"]& /@ Take[$segs, UpTo[3]], "\n---\n"] <> "\n\n", ""];
  prompt = ctx <> "以下はプレゼンテーションの最新の書き起こしです：\n\n" <> para <>
    "\n\n上記の内容を深く分析し、解説してください。";

  (* マルチモーダル: スライドがあればBase64画像を添付 *)
  If[Length[$pSlides] > 0,
    sysPrompt = plSysPrompt[True];
    imgParts = (<|"type" -> "image", "source" -> <|
      "type" -> "base64", "media_type" -> "image/jpeg",
      "data" -> #["b64"]|>|>) & /@ $pSlides;
    userContent = Join[
      {<|"type" -> "text", "text" -> prompt <> "\n\n（" <>
        ToString[Length[$pSlides]] <> "枚のスライド添付）"|>},
      imgParts],
    sysPrompt = plSysPrompt[False];
    userContent = prompt];

  reqF = FileNameJoin[{$tmpDir, "comm_req.json"}];
  $pOut = FileNameJoin[{$tmpDir, "comm_resp.json"}];
  $pReq = reqF;
  plWriteJSON[reqF, <|
    "model" -> "claude-sonnet-4-6",
    "max_tokens" -> 4096,
    "system" -> sysPrompt,
    "messages" -> {<|"role" -> "user", "content" -> userContent|>}|>];
  $pProc = Quiet@Check[StartProcess[{
    "curl", "-s", "--max-time", "180",
    "-o", $pOut, "-X", "POST",
    "https://api.anthropic.com/v1/messages",
    "-H", "Content-Type: application/json; charset=utf-8",
    "-H", "x-api-key: " <> k,
    "-H", "anthropic-version: 2023-06-01",
    "--data-binary", "@" <> reqF}], None];
  If[$pProc =!= None, $pSt = "commenting", $pSt = "idle"]
]

(* ============================================================ *)
(*  🔧標準パス: ClaudeQueryAsync (CLI優先 + Fallback)             *)
(* ============================================================ *)

startStandardCorrection[rawText_String] := (
  $pSt = "llmBusy";
  ClaudeQueryAsync[$correctP <> "\n\n" <> rawText,
    Function[corrected0, Module[{corrected = corrected0},
      If[!StringQ[corrected] || corrected === $Failed ||
         StringStartsQ[ToString[corrected], "Error:"],
        corrected = rawText];
      corrected = StringTrim[corrected];
      If[StringLength[corrected] == 0 || refusalQ[corrected], corrected = rawText];
      $prevText = StringTake[corrected, -Min[StringLength[corrected], 200]];
      $buf = If[$buf === "", corrected, $buf <> " " <> corrected];
      $transcript = $transcript <> corrected <> "\n";
      If[StringLength[$buf] >= $minPara,
        startStandardCommentary[$buf]; $buf = "",
        $pSt = "idle"]]],
    $nb, Fallback -> billingAllowed[]])

startStandardCommentary[para_String] := Module[{ctx, prompt, sysPrompt, imgs},
  $pPara = para; $pSlides = $slideBuffer; $slideBuffer = {};
  ctx = If[Length[$segs] > 0,
    "これまでの内容：\n" <> StringRiffle[#["text"]& /@ Take[$segs, UpTo[3]], "\n---\n"] <> "\n\n", ""];
  prompt = ctx <> "以下はプレゼンテーションの最新の書き起こしです：\n\n" <> para <>
    "\n\n上記の内容を深く分析し、解説してください。";
  sysPrompt = plSysPrompt[Length[$pSlides] > 0];
  If[Length[$pSlides] > 0,
    prompt = prompt <> "\n\n（" <> ToString[Length[$pSlides]] <> "枚のスライド添付）"];
  imgs = If[Length[$pSlides] > 0, #["img"] & /@ $pSlides, {}];
  (* 標準モード: 画像はファイルパスで渡す (CLI読み取り) *)
  If[Length[imgs] > 0 && !billingAllowed[],
    Module[{imgPaths = {}, augPrompt, tmpD, i = 0},
      tmpD = $tmpDir;
      Do[i++; Module[{f = FileNameJoin[{tmpD, "slide_std_" <> ToString[i] <> ".jpg"}]},
        Export[f, im, "JPEG", ImageResolution -> 100];
        AppendTo[imgPaths, f]], {im, imgs}];
      augPrompt = sysPrompt <> "\n\n---\n\n" <> prompt <>
        "\n\n【スライド画像ファイル】\n" <> StringRiffle[("- " <> #) & /@ imgPaths, "\n"];
      ClaudeQueryAsync[augPrompt,
        Function[c0, Module[{c = c0},
          If[!StringQ[c] || c === $Failed, c = "[応答取得失敗]"];
          writeCommentarySection[$pPara, c, $pSlides]; $pSt = "idle"]],
        $nb, Fallback -> False]],
    (* 画像なしor課金許可: テキストのみ *)
    ClaudeQueryAsync[sysPrompt <> "\n\n---\n\n" <> prompt,
      Function[c0, Module[{c = c0},
        If[!StringQ[c] || c === $Failed, c = "[応答取得失敗]"];
        writeCommentarySection[$pPara, c, $pSlides]; $pSt = "idle"]],
      $nb, Fallback -> billingAllowed[]]
  ]]

(* ============================================================ *)
(*  解説セクション書き込み (共通)                                    *)
(* ============================================================ *)

writeCommentarySection[para_String, commentary0_String, slides_List] :=
Module[{n, title, bodyText, cells, commentary, translation},
  (* 発言が出力言語と異なるとき LLM は $plTrMarker の後に発言の訳を付ける *)
  {commentary, translation} = splitTranslation[commentary0];
  AppendTo[$segs, <|"text" -> para, "commentary" -> commentary,
    "translation" -> translation,
    "time" -> elapsed[], "timestamp" -> Now, "slides" -> (#["img"]& /@ slides)|>];
  n = Length[$segs]; title = extractTitle[commentary]; bodyText = stripTitle[commentary];
  (* タイトルが読み取れたら 既定 SourceVault フォルダへ保存し参照登録する (初回のみ)。
     これにより以降のキャプチャ画像・発言・解説が保存済みノートに記録される。 *)
  If[!$nbSaved && StringQ[title] && title =!= "---" && StringLength[title] >= 2,
    plSaveNotebook[title]];
  cells = {Cell[ToString[n] <> "  " <> title <> "  [" <> elapsed[] <> "]", "Subsection"]};
  Do[AppendTo[cells, Cell[BoxData[ToBoxes[Column[{
    Style["Slide [" <> s["time"] <> "]", Gray, Italic, 9],
    Show[s["img"], ImageSize -> 500]}, Spacings -> 0.2]]], "Output",
    CellMargins -> {{30, 20}, {3, 3}}]], {s, slides}];
  AppendTo[cells, Cell[TextData[{
    StyleBox["Speech: ", FontWeight -> Bold, FontSize -> 10, FontColor -> GrayLevel[0.6]],
    StyleBox[para, FontSize -> 10, FontColor -> GrayLevel[0.6], FontSlant -> Italic]}], "Text"]];
  If[StringLength[translation] > 0,
    AppendTo[cells, Cell[TextData[{
      StyleBox["Translation: ", FontWeight -> Bold, FontSize -> 10, FontColor -> GrayLevel[0.4]],
      StyleBox[translation, FontSize -> 11, FontColor -> GrayLevel[0.3]]}], "Text"]]];
  AppendTo[cells, Cell[bodyText, "Text", Background -> RGBColor[0.95, 0.97, 1.0],
    CellFrame -> {{2, 0}, {0, 0}}, CellFrameColor -> RGBColor[0.2, 0.4, 0.8],
    CellMargins -> {{30, 20}, {5, 5}}, FontSize -> 13]];
  wr[Cell[CellGroupData[cells, Open]]];
  plPersistNotebook[];   (* 画像を含む最新状態を保存済みノートファイルへ反映 *)
  (* SourceVault 融合: 発言(transcript)と解説を session event として ingest *)
  plSVAppend["ASRTranscript", para];
  plSVSummary[commentary]]

(* ============================================================ *)
(*  公開API                                                       *)
(* ============================================================ *)

Options[StartListener] = {"Device" -> Automatic, "VideoDevice" -> Automatic,
  "Language" -> Automatic, "OutputLanguage" -> Automatic, "AudioOnly" -> Automatic,
  "ChunkDuration" -> 60, "MinParagraphLength" -> 80,
  "CaptureInterval" -> 15, "SlideThreshold" -> 0.08, "SourceVaultSync" -> True,
  "AutoCropSlide" -> False, "SlideMaxWidth" -> 1280, "NotebookFolder" -> Automatic};

(* Start 失敗時に理由を必ず残す。ボタン (Method->"Queued") からは戻り値が
   見えないため、$lastStartMsg をパレットの Dynamic で可視化する。 *)
startFail[msg_String] := ($running = False; $lastStartMsg = msg;
  Print[Style["StartListener 失敗: " <> msg, RGBColor[0.7, 0.1, 0.1], Bold]]; msg)

StartListener[OptionsPattern[]] := Module[{d, vd, k},
  If[$running, Return["Already running."]];
  If[!ffmpegAvailableQ[],
    Return[startFail[$ffmpegMissingMsg]]];
  d = OptionValue["Device"];
  (* 未指定(Automatic)なら ShowSettings/パレットで保存した設定 ($cfgDevice) を使う。
     $cfgDevice も Automatic なら既定マイクを解決する。 *)
  If[d === Automatic, d = resolveAudioDevice[$cfgDevice]];
  If[d === None,
    Return[startFail["音声デバイスを解決できませんでした。ShowSettings[] で選択するか、\"Device\"->\"<デバイス名>\" を明示してください (ListAudioDevices[] で一覧)。"]]];
  k = whisperAPIKey[];
  If[k === $Failed,
    (* 2026-08-06: 登録済みかの確認のみ。値は取らない (NBAccess の正規口) *)
    Module[{raw = Quiet@Check[NBAccess`NBCredentialConfiguredQ["OPENAI_API_KEY"], False]},
      If[TrueQ[raw],
        Return[startFail["OpenAI キーは登録済みですが取得が拒否されました。$NBPrivacySpec の AccessLevel を確認してください。"]],
        Return[startFail["Whisper 用 OpenAI キーが未登録です。SystemCredential[\"OPENAI_API_KEY\"] を設定してください。"]]]]];
  vd = OptionValue["VideoDevice"];
  (* 未指定(Automatic)なら設定済み映像デバイス ($cfgVideoDevice) を使う。
     映像を使わないときは明示的に "VideoDevice"->None を渡す。 *)
  If[vd === Automatic, vd = resolveVideoDevice[$cfgVideoDevice]];
  (* 音声のみ: カメラは開かない。解決したデバイスは途中で画像+音声へ戻すときのために残す *)
  If[BooleanQ[OptionValue["AudioOnly"]], $ListenerAudioOnly = OptionValue["AudioOnly"]];
  $vidDevSaved = vd;
  If[TrueQ[$ListenerAudioOnly], vd = None];
  $lang = OptionValue["Language"]; $outLang = OptionValue["OutputLanguage"];
  $chunkSec = OptionValue["ChunkDuration"];
  $minPara = OptionValue["MinParagraphLength"];
  $captureIntv = OptionValue["CaptureInterval"]; $slideThresh = OptionValue["SlideThreshold"];
  $slideAutoCrop = TrueQ[OptionValue["AutoCropSlide"]];
  $slideMaxWidth = OptionValue["SlideMaxWidth"];
  $svNBFolder = OptionValue["NotebookFolder"];
  $dev = d; $vidDev = vd;
  $tmpDir = Quiet@Check[CreateDirectory[FileNameJoin[{$TemporaryDirectory,
    "PA" <> DateString[{"Year","Month","Day","Hour","Minute","Second"}]}]], $Failed];
  If[!StringQ[$tmpDir] || !DirectoryQ[$tmpDir],
    Return[startFail["一時ディレクトリの作成に失敗しました。"]]];
  $transcript = ""; $buf = ""; $segs = {}; $queue = {}; $prevText = ""; $queuedSet = {};
  $slideBuffer = {}; $prevFrameImg = None; $lastCapTime = None; $slideCount = 0;
  $nbPath = None; $nbSaved = False;
  $running = True; $start = Now; $errs = {}; $lastStartMsg = "";
  (* SourceVault 融合: 同期 ON かつ SourceVault ロード済みならセッションを開始 *)
  $plSVSync = TrueQ[OptionValue["SourceVaultSync"]];
  $plSVSession = If[$plSVSync,
    "presentation-" <> DateString[{"Year", "Month", "Day", "Hour", "Minute", "Second"}, TimeZone -> 0],
    None];
  $tickCount = 0; $lastTickTime = None; $lastSegCount = 0; $lastSegList = {};
  $pSt = "idle"; $pProc = None; $recProc = None; $pSlides = {};
  makeNB[];
  wr[Cell[ts[] <> " - Started v22 (" <>
    If[effectiveFastMode[], "⚡curl直接", "🔧CLI優先"] <> ", lang=" <>
    ToString[Replace[plWhisperLang[$lang], None -> "auto"]] <> "→" <> plOutLang[] <> ", billing=" <>
    If[billingAllowed[], "ON", "OFF"] <> ", video=" <>
    Which[vd =!= None, "ON", TrueQ[$ListenerAudioOnly], "OFF 音声のみ", True, "OFF"] <> ")",
    "Text", FontColor -> RGBColor[0.1, 0.5, 0.1], FontWeight -> Bold]];
  If[plSVAvailableQ[],
    wr[Cell["SourceVault session: " <> $plSVSession <>
      "  (SourceVaultGetLiveTranscript / SourceVaultGetLiveSummary で参照可)",
      "Text", FontColor -> GrayLevel[0.5], FontSize -> 10]]];
  startContinuousRecording[];
  If[$recProc === None,
    $running = False;
    If[$task =!= None, Quiet@RemoveScheduledTask[$task]; $task = None];
    wr[Cell[ts[] <> " - 録音プロセスの起動に失敗しました (device=" <> ToString[$dev] <> ")",
      "Text", FontColor -> RGBColor[0.7, 0.1, 0.1], FontWeight -> Bold]];
    Return[startFail["ffmpeg 録音プロセスの起動に失敗しました。デバイス名「" <>
      ToString[$dev] <> "」を確認してください。"]]];
  $task = RunScheduledTask[tick[], 1];
  $lastStartMsg = "Started.";
  "Started."]

StopListener[] := (
  $running = False;
  If[$recProc =!= None, Quiet@Check[If[ProcessStatus[$recProc] === "Running", KillProcess[$recProc]], Null]];
  $recProc = None;
  plAbortAll[];
  If[$task =!= None, Quiet@RemoveScheduledTask[$task]; $task = None];
  Quiet@VoiceQuestionStop[];   (* 自分で開いた音声セッション (GPT-Live は接続時間で課金) も閉じる *)
  If[DirectoryQ[$tmpDir], Quiet@DeleteDirectory[$tmpDir, DeleteContents -> True]];
  wr[Cell[ts[] <> " - Stopped (" <> ToString[Length[$segs]] <> " segments)",
    "Text", FontColor -> RGBColor[0.8, 0.2, 0.2], FontWeight -> Bold]];
  (* タイトルが一度も読めず未保存なら、内容を失わないよう既定名で保存する *)
  If[!$nbSaved && nbOK[] && Length[$segs] > 0, plSaveNotebook["presentation"]];
  plPersistNotebook[];   (* 最終状態をファイルへ反映 *)
  plIndexNotebook[];     (* SourceVault に即時 index 化 (snapshot/SymbolicPath を確定) *)
  plSVAppend["SystemSummary", "発表記録を終了しました (" <> ToString[Length[$segs]] <> " セグメント)"];
  "Stopped.")

ResumeListener[] := (
  If[$running, Return["Already running."]];
  If[!nbOK[], makeNB[]]; If[$dev === None, Return["No device."]];
  If[!DirectoryQ[$tmpDir], $tmpDir = CreateDirectory[FileNameJoin[{$TemporaryDirectory,
    "PA" <> DateString[{"Year","Month","Day","Hour","Minute","Second"}]}]]];
  $running = True; $pSt = "idle"; $queue = {}; $queuedSet = {};
  $slideBuffer = {}; $prevFrameImg = None; $lastCapTime = None;
  wr[Cell[ts[] <> " - Resumed", "Text", FontColor -> RGBColor[0.2, 0.6, 0.2], FontWeight -> Bold]];
  startContinuousRecording[]; $task = RunScheduledTask[tick[], 1]; "Resumed.")

(* ============================================================ *)
(*  AskQuestion / ExportSession                                    *)
(* ============================================================ *)

parseSecRef[q_String] := StringCases[q, "#" ~~ n : DigitCharacter .. :> ToExpression[n]]
buildSectionText[seg_Association, idx_Integer] := StringJoin[
  "=== セクション #", ToString[idx], " [", seg["time"], "] ===\n",
  "【発言】\n", seg["text"], "\n",
  If[StringLength[Lookup[seg, "translation", ""]] > 0,
    "【発言の訳】\n" <> seg["translation"] <> "\n", ""],
  "【解説】\n", seg["commentary"], "\n"]
sectionImages[seg_Association] := Lookup[seg, "slides", {}]

AskQuestion[q_String] := Module[{refs, allText, imgList, focusSegs, prompt},
  If[!nbOK[], Return["No notebook."]]; refs = parseSecRef[q]; imgList = {};
  If[Length[$segs] == 0,
    allText = If[StringLength[$transcript] > 0, $transcript, "(内容なし)"],
    If[Length[refs] > 0,
      allText = "【全体概要】\n" <> StringRiffle[MapIndexed[
        ("セクション #" <> ToString[#2[[1]]] <> " [" <> #1["time"] <> "]: " <> extractTitle[#1["commentary"]]) &,
        $segs], "\n"] <> "\n\n【指定セクション詳細】\n";
      focusSegs = Select[refs, 1 <= # <= Length[$segs] &];
      allText = allText <> StringRiffle[buildSectionText[$segs[[#]], #] & /@ focusSegs, "\n"];
      imgList = Join @@ (sectionImages[$segs[[#]]] & /@ focusSegs),
      allText = StringRiffle[MapIndexed[buildSectionText[#1, #2[[1]]] &, $segs], "\n"];
      imgList = If[Length[$segs] > 0, sectionImages[Last[$segs]], {}]]];
  prompt = "プレゼンテーション記録を活用し、質問に正確かつ深く回答してください。" <>
    "回答は " <> plLangName[plOutLang[]] <> " で書いてください（記録が別の言語でも）。\n\n---\n\n" <>
    allText <> If[Length[imgList] > 0, "\n\n（" <> ToString[Length[imgList]] <> "枚のスライド添付）", ""] <>
    "\n\n質問：\n" <> q;
  wr[Cell["Q: " <> q, "Text", FontWeight -> "Bold", FontSize -> 14, CellMargins -> {{30, 20}, {8, 4}}]];
  plSVAppend["UserQuestion", q];   (* SourceVault 融合: 質問を記録 *)
  (* Q&A は常に ClaudeQueryAsync (深い回答のためCLI優先) *)
  ClaudeQueryAsync[prompt,
    Function[ans0, Module[{ans = ans0},
      If[!StringQ[ans] || ans === $Failed, ans = "[応答取得失敗]"];
      wr[Cell[ans, "Text", Background -> RGBColor[0.95, 0.97, 1.0],
        CellFrame -> {{2, 0}, {0, 0}}, CellFrameColor -> RGBColor[0.3, 0.5, 0.9],
        CellMargins -> {{30, 20}, {5, 5}}, FontSize -> 13]];
      plSVAppend["ResponseDraft", ans]]],   (* SourceVault 融合: 回答を記録 *)
    $nb, Fallback -> billingAllowed[]];
  "質問を送信しました。"]

AskQuestion[q_] := AskQuestion[ToString[q]]

(* ============================================================ *)
(*  VoiceQuestion: 発表者に声で質問し、声の回答を文字で残す         *)
(*  音声は SourceVault_realtime (SlideWorkflow と同じ gpt-live /     *)
(*  gpt-realtime のブリッジ)。流れ:                                 *)
(*    質問 → 発表者の言語へ翻訳 (LLM) → Narrate で読み上げ           *)
(*    → 読み終えたらマイクを開き、発表者の発話の書き起こしを集める   *)
(*    → 黙って $VoiceQuestionSilence 秒 (または「回答を確定」)       *)
(*    → 原文セルをすぐ書き、$Language へ訳したセルを続けて書く。     *)
(*  翻訳を音声モデルにさせないのは、GPT-Live の読了判定が「原稿の    *)
(*  8 割を言ったか」だから (訳しながら読むと原稿と一致しない)。       *)
(*  読み上げ以外はモデルに話させない: 待機中はマイクを閉じ、回答中に *)
(*  話し出したら止める。                                             *)
(* ============================================================ *)

$vqSt = "idle"; $vqStatus = ""; $vqTask = None; $vqOwnSession = False;
$vqQ = ""; $vqSpoken = None; $vqSpeakerLang = None; $vqId = "";
$vqT0 = 0; $vqParts = <||>; $vqSeq0 = 0; $vqLastUser = ""; $vqChangeT = 0;
$vqCancelT = 0; $vqFinish = False; $vqIdleSince = 0; $vqPrevMuted = None; $vqJobs = {};

vqRealtimeQ[] := Length[DownValues[SourceVault`SourceVaultRealtimeStart]] > 0

vqModel[] := Which[
  StringQ[$VoiceQuestionModel] && StringTrim[$VoiceQuestionModel] =!= "", $VoiceQuestionModel,
  Length[DownValues[SlideWorkflow`Private`iSWVoiceModel]] > 0,
    Replace[Quiet@Check[SlideWorkflow`Private`iSWVoiceModel[], "gpt-live-1"],
      Except[_String] -> "gpt-live-1"],
  True, "gpt-live-1"]

(* 読み上げ以外で口を開かせないための指示。GPT-Live はセッションの指示を
   常に持ち続けるので、ここは「役割」だけを書く (命令形の読み上げ依頼は書かない)。 *)
$vqInstructions = "あなたは発表会場の質問の取り次ぎ役です。\
アプリから渡される原稿は、聴衆から発表者への質問です。原稿は書かれたとおりの言語と文言で伝えます。\
それ以外の場面では何も話しません。発表者の回答には返事・相づち・お礼・要約・感想を言わず、\
質問に自分で答えることもしません。";

vqSay[s_String] := ($vqStatus = s)

(* 文字種で言語を大まかに見る。翻訳を省けるか (同じ言語か) の判定だけに使う *)
vqScript[t_String] := Which[
  StringContainsQ[t, RegularExpression["[\\x{3040}-\\x{30FF}]"]], "Japanese",
  StringContainsQ[t, RegularExpression["[\\x{AC00}-\\x{D7AF}]"]], "Korean",
  StringContainsQ[t, RegularExpression["[\\x{4E00}-\\x{9FFF}]"]], "Chinese",
  StringContainsQ[t, RegularExpression["[A-Za-z]"]], "Latin",
  True, None]
vqScript[_] := None

vqLangScript[l_String] := Switch[l,
  "Japanese" | "ja", "Japanese", "Korean" | "ko", "Korean",
  "Chinese" | "ChineseSimplified" | "ChineseTraditional" | "zh", "Chinese",
  _, None]
vqLangScript[_] := None

(* 発表者の言語の手がかり: 明示の "Language"、無ければ最近の書き起こし *)
vqSpeakerSample[] := Module[{t = $transcript},
  If[!StringQ[t] || StringTrim[t] === "",
    t = StringRiffle[Lookup[#, "text", ""] & /@ Take[$segs, -Min[2, Length[$segs]]], "\n"]];
  If[StringLength[t] > 600, StringTake[t, -600], t]]

(* LLM の返答から前置き・引用符・コードフェンスを落とす *)
vqClean[s_String] := StringTrim[StringReplace[StringTrim[s], {
  StartOfString ~~ "```" ~~ Shortest[___] ~~ "\n" -> "", "```" ~~ EndOfString -> ""}]]

vqOK[r_] := StringQ[r] && !StringStartsQ[r, "Error:"] && !StringStartsQ[r, "[API Error"] &&
  StringTrim[r] =!= ""

(* 翻訳は短いので ⚡高速モードでは解説と同じ curl 直叩き (vqTick が待つ)。
   🔧標準モードは ClaudeQueryAsync。どちらも cb[訳 | $Failed] を呼ぶ。 *)
vqLLM[prompt_String, cb_] := Module[{k = If[effectiveFastMode[], anthropicAPIKey[], $Failed],
    dir, id, req, out, proc},
  If[k =!= $Failed,
    dir = If[StringQ[$tmpDir] && DirectoryQ[$tmpDir], $tmpDir, $TemporaryDirectory];
    id = StringReplace[CreateUUID[], "-" -> ""];
    req = FileNameJoin[{dir, "vq_req_" <> id <> ".json"}];
    out = FileNameJoin[{dir, "vq_resp_" <> id <> ".json"}];
    plWriteJSON[req, <|"model" -> "claude-sonnet-4-6", "max_tokens" -> 2048,
      "messages" -> {<|"role" -> "user", "content" -> prompt|>}|>];
    proc = Quiet@Check[StartProcess[{"curl", "-s", "--max-time", "60", "-o", out, "-X", "POST",
      "https://api.anthropic.com/v1/messages",
      "-H", "Content-Type: application/json; charset=utf-8", "-H", "x-api-key: " <> k,
      "-H", "anthropic-version: 2023-06-01", "--data-binary", "@" <> req}], None];
    If[Head[proc] === ProcessObject,
      AppendTo[$vqJobs, <|"Process" -> proc, "Request" -> req, "Out" -> out, "Callback" -> cb|>];
      vqEnsureTask[]; Return[Null]]];
  ClaudeQueryAsync[prompt,
    Function[r, cb[If[vqOK[r], vqClean[r], $Failed]]],
    $nb, Fallback -> billingAllowed[]]]

vqPollJobs[] := Module[{done},
  done = Select[$vqJobs, ProcessStatus[#["Process"]] =!= "Running" &];
  If[done === {}, Return[]];
  $vqJobs = Complement[$vqJobs, done];
  Scan[Function[j, Module[{r = plExtractText[plReadJSON[j["Out"]]]},
      Quiet@DeleteFile[{j["Out"], j["Request"]}];
      j["Callback"][If[vqOK[r], vqClean[r], $Failed]]]], done]]

(* 質問を発表者の言語へ。1 行目 LANG: <英語の言語名>、2 行目以降が質問文 *)
vqTranslateQuestion[q_String] := Module[{sample = vqSpeakerSample[], explicit, qs},
  explicit = If[StringQ[$lang] && StringTrim[$lang] =!= "", $lang, None];
  qs = vqScript[q];
  (* 同じ文字種 (日本語・韓国語・中国語) なら訳さずに読む = 待ち時間なし *)
  If[qs =!= None && qs =!= "Latin" &&
      (vqLangScript[explicit] === qs || (explicit === None && vqScript[sample] === qs)),
    $vqSpeakerLang = qs; $vqSpoken = q; Return[]];
  If[explicit === None && StringTrim[sample] === "",
    (* 発表者の言語の手がかりが無い: 質問をそのまま読む *)
    $vqSpeakerLang = None; $vqSpoken = q; Return[]];
  vqSay["質問を訳しています…"];
  vqLLM[
    "You relay an audience question to a presenter by voice. Rewrite the question in the " <>
    "presenter's language as natural, polite spoken language (keep technical terms accurate; " <>
    "if it is already in that language, keep it as is).\n" <>
    If[StringQ[explicit], "The presenter speaks: " <> plLangName[explicit] <> "\n",
      "Identify the presenter's language from this recent transcript of the talk:\n<<<\n" <>
        sample <> "\n>>>\n"] <>
    "Output exactly two parts: first line `LANG: <language name in English>`, then the question text only " <>
    "(no quotes, no notes).\n\nQuestion:\n" <> q,
    Function[r, Module[{lines, lang, text},
      If[!StringQ[r], $vqSpoken = q; Return[]];
      lines = StringSplit[r, "\n"];
      lang = SelectFirst[lines, StringStartsQ[StringTrim[#], "LANG:", IgnoreCase -> True] &, None];
      text = StringTrim[StringRiffle[DeleteCases[lines, lang], "\n"]];
      $vqSpeakerLang = If[StringQ[lang],
        StringTrim[StringDrop[StringTrim[lang], 5]], None];
      $vqSpoken = If[text === "", q, text]]]]]

vqFail[msg_String] := (
  vqDone[];
  vqWrite[Cell["VoiceQuestion: " <> msg, "Text", FontColor -> RGBColor[0.7, 0.1, 0.1], FontSize -> 11]];
  vqSay[msg]; msg)

vqWrite[cell_] := wr[cell]

vqEnsureSession[] := Module[{st, r, nb},
  If[!vqRealtimeQ[],
    Return["SourceVault_realtime.wl が読み込まれていません (SourceVault をロードしてください)。"]];
  st = SourceVault`SourceVaultRealtimeStatus[];
  (* 他 (SlideWorkflow の発表など) が開いたセッションは借りるだけ: 終わったらミュートを戻す *)
  If[TrueQ[st["Running"]],
    If[!$vqOwnSession, $vqPrevMuted = TrueQ[st["Muted"]]];
    Return[True]];
  $vqPrevMuted = None;
  If[!billingAllowed[], Return["課金API が「禁止」です。音声質問は OpenAI の音声 API (有料) を使います。"]];
  nb = $nb;
  (* 課金の承認はパレットの「課金API: 許可」で受けている (ノート単位の承認は求めない) *)
  r = SourceVault`SourceVaultRealtimeStart["Model" -> vqModel[], "Notebook" -> nb,
    "Instructions" -> $vqInstructions, "StartMuted" -> True, "TranscribeInput" -> True,
    "AllowBargeIn" -> False, "RequirePaidAPIApproval" -> False,
    "StatusBar" -> (Head[nb] === NotebookObject)];
  If[FailureQ[r], Return[Replace[r["Message"], Except[_String] -> "音声セッションを開始できませんでした。"]]];
  $vqOwnSession = True;
  True]

vqStopSession[] := (
  If[$vqOwnSession && vqRealtimeQ[], Quiet@SourceVault`SourceVaultRealtimeStop[]];
  $vqOwnSession = False)

vqEnsureTask[] := If[$vqTask === None, $vqTask = RunScheduledTask[vqTick[], 0.5]]
vqStopTask[] := (If[$vqTask =!= None, Quiet@RemoveScheduledTask[$vqTask]]; $vqTask = None)

VoiceQuestion[q_String] := Module[{ok},
  If[StringTrim[q] === "", Return["質問が空です。"]];
  If[$vqSt =!= "idle", Return["前の音声質問がまだ終わっていません (VoiceQuestionFinish[] で回答を確定)。"]];
  If[!nbOK[], makeNB[]];   (* 聞き取り前でも書き出し先を用意する *)
  $vqQ = StringTrim[q]; $vqSpoken = None; $vqSpeakerLang = None;
  $vqParts = <||>; $vqFinish = False;
  $vqId = "vq-" <> StringReplace[CreateUUID[], "-" -> ""];
  vqWrite[Cell[TextData[{StyleBox["🎤 Q (発表者へ音声で): ", FontColor -> RGBColor[0.55, 0.25, 0.1]], $vqQ}],
    "Text", FontWeight -> "Bold", FontSize -> 14, CellMargins -> {{30, 20}, {8, 4}}]];
  plSVAppend["UserQuestion", $vqQ];
  $vqSt = "preparing"; $vqT0 = AbsoluteTime[];
  vqEnsureTask[];
  vqTranslateQuestion[$vqQ];     (* 非同期。訳している間に接続する *)
  vqSay["音声セッションに接続しています…"];
  ok = vqEnsureSession[];
  If[ok =!= True, Return[vqFail[ok]]];
  "音声質問を開始しました。"]
VoiceQuestion[q_] := VoiceQuestion[ToString[q]]

VoiceQuestionFinish[] := If[$vqSt === "listening", $vqFinish = True; "回答を確定します。",
  "回答待ちではありません。"]

VoiceQuestionStop[] := (
  If[$vqSt =!= "idle" && vqRealtimeQ[], Quiet@SourceVault`SourceVaultRealtimeCancel[]];
  Scan[Quiet@KillProcess[#["Process"]] &, $vqJobs]; $vqJobs = {};
  $vqSt = "idle"; vqSay[""]; vqStopSession[]; vqStopTask[]; "Stopped.")

VoiceQuestionStatus[] := <|"State" -> $vqSt, "Status" -> $vqStatus, "Model" -> vqModel[],
  "SpeakerLanguage" -> $vqSpeakerLang, "Spoken" -> $vqSpoken, "OwnSession" -> $vqOwnSession,
  "Realtime" -> If[vqRealtimeQ[], SourceVault`SourceVaultRealtimeStatus[], None]|>

(* 回答の書き起こしを集める。ワーカーの履歴は 40 行で切れるので毎回拾っておく *)
vqCollect[] := Module[{msgs, st, last},
  msgs = Quiet@Check[SourceVault`SourceVaultRealtimeMessages[], {}];
  Scan[If[#["Kind"] === "user" && #["Sequence"] > $vqSeq0 && !KeyExistsQ[$vqParts, #["Sequence"]],
      $vqParts[#["Sequence"]] = #["Text"]; $vqChangeT = AbsoluteTime[]] &,
    Select[msgs, AssociationQ]];
  st = SourceVault`SourceVaultRealtimeStatus[];
  last = Lookup[st, "LastUserText", ""];
  If[StringQ[last] && last =!= $vqLastUser, $vqLastUser = last; $vqChangeT = AbsoluteTime[]];
  st]

(* まだ履歴に載っていない話しかけ (GPT-Live は 1.5 s 黙るまで行を閉じない) も含めた回答 *)
vqNorm[t_String] := StringTrim[StringReplace[t, Whitespace -> " "]]
vqAnswerText[] := Module[{parts = Values[KeySort[$vqParts]], tail = $vqLastUser},
  If[StringQ[tail] && vqNorm[tail] =!= "" && tail =!= $vqBaseUser &&
      !AnyTrue[parts, StringContainsQ[vqNorm[#], vqNorm[tail]] &],
    AppendTo[parts, tail]];
  StringTrim[StringRiffle[parts, " "]]]
$vqBaseUser = "";

vqTick[] := Quiet@Check[(vqPollJobs[]; vqStep[]), Null]

vqStep[] := Module[{now = AbsoluteTime[], st},
  Switch[$vqSt,
  "preparing",
    If[now - $vqT0 > 45, vqFail["音声セッションの準備が 45 秒で終わりませんでした。"]; Return[]];
    If[!StringQ[$vqSpoken], Return[]];
    st = SourceVault`SourceVaultRealtimeStatus[];
    If[!TrueQ[st["Running"]], vqFail["音声セッションが終了しました: " <> ToString[st["LastError"]]]; Return[]];
    If[!TrueQ[st["Connected"]], vqSay["接続を待っています…"]; Return[]];
    If[$vqSpoken =!= $vqQ,
      vqWrite[Cell[TextData[{StyleBox["読み上げ" <>
          If[StringQ[$vqSpeakerLang], " (" <> $vqSpeakerLang <> ")", ""] <> ": ",
          FontWeight -> Bold, FontColor -> GrayLevel[0.55]],
        StyleBox[$vqSpoken, FontColor -> GrayLevel[0.4]]}], "Text", FontSize -> 11,
        CellMargins -> {{30, 20}, {2, 2}}]]];
    SourceVault`SourceVaultRealtimeMute[True];
    SourceVault`SourceVaultRealtimeNarrate[$vqId, $vqSpoken, "Heading" -> "質問"];
    $vqSt = "speaking"; $vqT0 = now; vqSay["質問を読み上げています…"],

  "speaking",
    st = SourceVault`SourceVaultRealtimeStatus[];
    If[!TrueQ[st["Running"]], vqFail["音声セッションが終了しました。"]; Return[]];
    If[st["NarrationDone"] === $vqId || now - $vqT0 > 90,
      (* ここから先の発話だけが回答 *)
      $vqSeq0 = Max[0, Cases[Quiet@Check[SourceVault`SourceVaultRealtimeMessages[], {}],
        a_Association :> Lookup[a, "Sequence", 0]]];
      $vqBaseUser = Lookup[st, "LastUserText", ""]; $vqLastUser = $vqBaseUser;
      SourceVault`SourceVaultRealtimeMute[False];
      $vqSt = "listening"; $vqT0 = now; $vqChangeT = now; $vqCancelT = 0;
      vqSay["発表者の回答を聞いています… (回答を確定 で終了)"]],

  "listening",
    st = vqCollect[];
    If[!TrueQ[st["Running"]], $vqFinish = True];
    (* 取り次ぎ役が回答に口を挟んだら止める (3 s に 1 回まで) *)
    If[TrueQ[st["Speaking"]] && now - $vqCancelT > 3,
      $vqCancelT = now; Quiet@SourceVault`SourceVaultRealtimeCancel[]];
    If[TrueQ[$vqFinish] ||
        (vqAnswerText[] =!= "" && now - $vqChangeT > $VoiceQuestionSilence) ||
        (vqAnswerText[] === "" && now - $vqT0 > $VoiceQuestionNoAnswerSeconds) ||
        now - $vqT0 > $VoiceQuestionMaxSeconds,
      If[TrueQ[st["Running"]], SourceVault`SourceVaultRealtimeMute[True]];
      vqDeliverAnswer[vqAnswerText[]]],

  "translating", Null,

  "idle",
    (* 使い終わったセッションは $VoiceQuestionIdleSeconds で切る (GPT-Live は接続時間で課金) *)
    If[$vqOwnSession && now - $vqIdleSince > $VoiceQuestionIdleSeconds, vqStopSession[]];
    If[!$vqOwnSession && $vqJobs === {}, vqStopTask[]],
  _, Null]]

vqDone[] := (
  (* 借りたセッションは元のミュート状態へ戻す *)
  If[!$vqOwnSession && BooleanQ[$vqPrevMuted] && vqRealtimeQ[] &&
      TrueQ[SourceVault`SourceVaultRealtimeStatus[]["Running"]],
    SourceVault`SourceVaultRealtimeMute[$vqPrevMuted]];
  $vqSt = "idle"; $vqIdleSince = AbsoluteTime[]; vqSay[""])

vqAnswerCell[text_String] := Cell[TextData[{
    StyleBox["A (発表者): ", FontWeight -> Bold, FontColor -> RGBColor[0.2, 0.5, 0.25]], text}],
  "Text", Background -> RGBColor[0.95, 1.0, 0.95],
  CellFrame -> {{2, 0}, {0, 0}}, CellFrameColor -> RGBColor[0.25, 0.6, 0.3],
  CellMargins -> {{30, 20}, {5, 5}}, FontSize -> 13]

vqDeliverAnswer[ans_String] := Module[{out = plOutLang[], os},
  If[ans === "",
    vqWrite[Cell["(発表者の回答は聞き取れませんでした)", "Text", FontColor -> GrayLevel[0.5],
      FontSize -> 11, CellMargins -> {{30, 20}, {5, 5}}]];
    vqDone[]; Return[]];
  plSVAppend["ASRTranscript", "[VoiceQuestion の回答] " <> ans];
  os = vqLangScript[out];
  (* 出力言語と同じ文字種なら訳さずにそのまま出す *)
  If[os =!= None && vqScript[ans] === os,
    vqWrite[vqAnswerCell[ans]]; vqDone[]; Return[]];
  (* 原文はすぐ出し、訳は届いたら続ける *)
  vqWrite[Cell[TextData[{
    StyleBox["Answer: ", FontWeight -> Bold, FontSize -> 10, FontColor -> GrayLevel[0.6]],
    StyleBox[ans, FontSize -> 10, FontColor -> GrayLevel[0.6], FontSlant -> Italic]}], "Text",
    CellMargins -> {{30, 20}, {2, 2}}]];
  $vqSt = "translating"; vqSay["回答を訳しています…"];
  vqLLM["Translate the presenter's spoken answer below into " <> plLangName[out] <>
    ". It is a speech transcript: keep the meaning faithfully, fix obvious recognition errors " <>
    "using the question as context, and do not summarize. If it is already in " <> plLangName[out] <>
    ", return it unchanged. Output the translation only.\n\nQuestion: " <> $vqQ <>
    "\n\nAnswer transcript:\n" <> ans,
    Function[r, (vqWrite[vqAnswerCell[If[StringQ[r], r, ans <> "  [翻訳失敗]"]]]; vqDone[])]]]

voiceQuestionDialog[] := Module[{q},
  If[$vqSt === "listening", VoiceQuestionFinish[]; Return[]];
  If[$vqSt =!= "idle", Return[]];
  q = DialogInput[DynamicModule[{text = ""},
    Column[{Style["発表者に声で質問", Bold, 13],
      Style["質問を発表者の言語で読み上げ、声の回答を " <> plLangName[plOutLang[]] <> " で書き出します。",
        9, GrayLevel[0.4]], Spacer[5],
      InputField[Dynamic[text], String, FieldSize -> {50, 5}], Spacer[5],
      Row[{DefaultButton["読み上げる", DialogReturn[text]], Spacer[20],
        CancelButton["キャンセル", DialogReturn[$Canceled]]}]}, Spacings -> 0.5]],
    WindowTitle -> "Voice Question"];
  If[q === $Canceled || !StringQ[q] || StringTrim[q] === "", Return[]];
  VoiceQuestion[q]]

GetTranscript[] := If[$transcript === "", "(empty)", $transcript]
GetSegments[] := $segs
ExportSession[fn_String] := Module[{c, f},
  c = "# Session " <> DateString[] <> "\n\n" <>
    If[Length[$segs] > 0,
      StringRiffle[("## " <> #["time"] <> "\n" <> #["text"] <> "\n\n" <>
          If[StringLength[Lookup[#, "translation", ""]] > 0, "> " <> #["translation"] <> "\n\n", ""] <>
          #["commentary"])& /@ $segs,
        "\n\n---\n\n"], "(none)"] <> "\n\n---\n# Transcript\n\n" <> $transcript;
  f = If[FileExtension[fn] === "", fn <> ".md", fn]; Export[f, c, "Text"]]

(* ============================================================ *)
(*  ProcessCells (iWriteQueryResponse 共有)                       *)
(* ============================================================ *)

cellHasGraphicsQ[expr_] := Or @@ (!FreeQ[expr, #] & /@ {GraphicsBox, RasterBox, Graphics3DBox, Raster3DBox})
cellToText[Cell[s_String, style_String, ___]] := "[" <> style <> "] " <> s
cellToText[Cell[TextData[parts_], style_String, ___]] := "[" <> style <> "] " <> StringJoin[tdPart /@ Flatten[{parts}]]
cellToText[Cell[BoxData[boxes_], style_String, ___]] :=
  If[cellHasGraphicsQ[boxes], "[" <> style <> "] (graphics omitted)",
    "[" <> style <> "] " <> Quiet@Check[ToString[RawBoxes[boxes], InputForm], ToString[boxes]]]
cellToText[Cell[CellGroupData[cells_List, _], ___]] :=
  StringRiffle[Select[cellToText /@ cells, StringQ[#] && StringLength[#] > 0 &], "\n\n"]
cellToText[_] := ""
tdPart[s_String] := s
tdPart[Cell[BoxData[boxes_], ___]] := Quiet@Check[ToString[RawBoxes[boxes], InputForm], ""]
tdPart[StyleBox[s_String, ___]] := s
tdPart[ButtonBox[s_String, ___]] := s
tdPart[other_] := Quiet@Check[ToString[other], ""]

imgToB64[img_Image] := Module[{f, bytes},
  f = FileNameJoin[{$TemporaryDirectory, "pa_pcell_" <> ToString[RandomInteger[999999]] <> ".png"}];
  Quiet@Check[Export[f, img, "PNG", ImageResolution -> 150], Return[None]];
  bytes = Quiet@Check[ReadByteArray[f], None]; Quiet@DeleteFile[f];
  If[ByteArrayQ[bytes], BaseEncode[bytes], None]]
imgToB64[_] := None

cellImageB64[cellExpr_] := Module[{imgs, b64s = {}, rimg, b64},
  imgs = Cases[cellExpr, img_Image :> img, Infinity]; b64s = Select[imgToB64 /@ imgs, StringQ];
  If[cellHasGraphicsQ[cellExpr],
    rimg = Quiet@Check[Rasterize[cellExpr, "Image", ImageResolution -> 150], $Failed];
    If[Head[rimg] === Image, b64 = imgToB64[rimg]; If[StringQ[b64], AppendTo[b64s, b64]]]];
  DeleteDuplicates@Select[b64s, StringQ]]

ProcessCells[prompt_String] := ProcessCells[prompt, InputNotebook[]]
ProcessCells[prompt_String, nb_] := Module[{selIdxs, cellExprs, allText, imgB64s,
    useAll, pLabel, phTag, truncated, limitedImgs, images, fullPrompt, nCells},
  If[!Quiet[Check[NBAccess`NBCellCount[nb]; True, False], All], Return[$Failed]];
  selIdxs = NBAccess`NBSelectedCellIndices[nb];
  useAll = (Length[selIdxs] == 0) || StringContainsQ[prompt, "全体" | "すべて" | "ノートブック"];
  nCells = NBAccess`NBCellCount[nb];
  If[useAll, selIdxs = Range[nCells]];
  cellExprs = Quiet[NBAccess`NBCellRead[nb, #] & /@ selIdxs];
  allText = StringRiffle[Select[cellToText /@ Flatten[{cellExprs}], StringQ[#] && StringLength[#] > 0 &], "\n\n"];
  imgB64s = Join @@ (cellImageB64 /@ Flatten[{cellExprs}]);
  pLabel = "P: " <> StringTake[prompt, UpTo[60]] <> If[StringLength[prompt] > 60, "...", ""];
  If[!useAll && Length[selIdxs] > 0,
    NBAccess`NBMoveAfterCell[nb, Last[selIdxs]], NBAccess`NBMoveToEnd[nb]];
  phTag = "pl-ph-" <> ToString[UnixTime[]] <> "-" <> ToString[RandomInteger[99999]];
  NBAccess`NBWriteCell[nb, Cell[pLabel <> "  [処理中...]", "Subsection", CellTags -> {phTag}]];
  truncated = If[StringLength[allText] > 120000, StringTake[allText, 120000] <> "\n\n[省略]", allText];
  limitedImgs = Take[imgB64s, UpTo[5]];
  fullPrompt = $processCellsP <> "\n\n---\n\n【ノートブック内容】\n" <> truncated <>
    If[Length[limitedImgs] > 0, "\n\n（" <> ToString[Length[limitedImgs]] <> "枚画像添付）", ""] <>
    "\n\n【プロンプト】\n" <> prompt;
  images = {};
  Do[Module[{bytes, img}, bytes = Quiet@Check[BaseDecode[b64], None];
    If[ByteArrayQ[bytes], img = Quiet@Check[ImportByteArray[bytes, "PNG"], None];
      If[ImageQ[img], AppendTo[images, img]]]], {b64, limitedImgs}];
  With[{nb0 = nb, l0 = pLabel, tag0 = phTag},
    ClaudeQueryAsync[fullPrompt,
      Function[ans0, Module[{ans = ans0},
        If[!StringQ[ans] || ans === $Failed, ans = "[処理失敗]"];
        NBAccess`NBDeleteCellsByTag[nb0, tag0];
        NBAccess`NBMoveToEnd[nb0];
        NBAccess`NBWriteCell[nb0, Cell[l0, "Subsection"]];
        ClaudeCode`Private`iWriteQueryResponse[nb0, ans]]],
      nb0, Fallback -> billingAllowed[]]]]

processDialog[] := Module[{prompt, targetNB},
  targetNB = InputNotebook[];
  prompt = DialogInput[DynamicModule[{text = ""},
    Column[{Style["Process Cells", Bold, 14], Spacer[5],
      Style["選択セルをAIに処理させます。", 10, GrayLevel[0.5]],
      Spacer[8], InputField[Dynamic[text], String, FieldSize -> {45, 5}], Spacer[10],
      Row[{DefaultButton["実行", DialogReturn[text]], Spacer[20],
        CancelButton["キャンセル", DialogReturn[$Canceled]]}]}, Spacings -> 0.5]],
    WindowTitle -> "Process Cells"];
  If[prompt === $Canceled || !StringQ[prompt] || StringTrim[prompt] === "", Return[]];
  ProcessCells[prompt, targetNB]]

(* ============================================================ *)
(*  設定                                                          *)
(* ============================================================ *)

$cfgDevice = Automatic; $cfgVideoDevice = Automatic;
$cfgCaptureIntv = 15; $cfgSlideThresh = 0.1; $palette = None;

resolveAudioDevice[Automatic] := Module[{dev}, dev = Quiet@getDefaultAudioDevice[];
  If[AssociationQ[dev], deviceId[dev], None]]
resolveAudioDevice[id_String] := id
resolveVideoDevice[Automatic] := Module[{vdevs}, vdevs = ListVideoDevices[];
  If[Length[vdevs] > 0, deviceId[vdevs[[1]]], None]]
resolveVideoDevice[""] := None; resolveVideoDevice[None] := None
resolveVideoDevice[id_String] := id

settingsDialog[] := Module[{result, aDevs, vDevs, aRules, vRules, note},
  refreshDevices[]; aDevs = ListAudioDevices[]; vDevs = ListVideoDevices[];
  (* 一覧が空のときは理由を出す (旧版は Default/Auto だけが黙って並んでいた) *)
  note = Which[
    !ffmpegAvailableQ[], $ffmpegMissingMsg,
    aDevs === {} && vDevs === {}, "ffmpeg (" <> $ffmpegExe <> ") が dshow デバイスを 1 つも返しませんでした。",
    True, None];
  aRules = Join[{Automatic -> "( Default )"}, (deviceId[#] -> #["name"]) & /@ aDevs];
  vRules = Join[{Automatic -> "( Auto )"}, {None -> "( None )"}, (deviceId[#] -> #["name"]) & /@ vDevs];
  result = DialogInput[DynamicModule[{selA = $cfgDevice, selV = $cfgVideoDevice,
      c = ToString[$cfgCaptureIntv], th = ToString[$cfgSlideThresh]},
    Column[{Style["Listener Settings", Bold, 14],
      If[StringQ[note], Pane[Style[note, RGBColor[0.7, 0.1, 0.1]], 380], Nothing], Spacer[10],
      Grid[{{Style["Audio:", Bold], PopupMenu[Dynamic[selA], aRules, ImageSize -> {280, Automatic}]},
        {Style["Video:", Bold], PopupMenu[Dynamic[selV], vRules, ImageSize -> {280, Automatic}]},
        {Style["Capture(s):", Bold], InputField[Dynamic[c], String, FieldSize -> 8]},
        {Style["Threshold:", Bold], InputField[Dynamic[th], String, FieldSize -> 8]}},
        Alignment -> {{Right, Left}}, Spacings -> {1, 1.0}], Spacer[10],
      Row[{DefaultButton["OK", DialogReturn[{selA, selV, c, th}]], Spacer[20],
        CancelButton["Cancel", DialogReturn[$Canceled]]}]}, Spacings -> 0.5]],
    WindowTitle -> "Settings"];
  If[result === $Canceled, Return[]];
  $cfgDevice = result[[1]]; $cfgVideoDevice = result[[2]];
  $cfgCaptureIntv = Quiet@Check[ToExpression[result[[3]]], 15];
  $cfgSlideThresh = Quiet@Check[ToExpression[result[[4]]], 0.1]]

(* デバイス設定ダイアログを単体で呼び出す公開 API (パレット非依存)。
   選択を $cfg* に保存し、解決後のデバイス ID を含む現在設定を返す。 *)
ShowSettings[] := (
  settingsDialog[];
  <|"Audio" -> $cfgDevice, "Video" -> $cfgVideoDevice,
    "CaptureInterval" -> $cfgCaptureIntv, "SlideThreshold" -> $cfgSlideThresh,
    "ResolvedAudio" -> resolveAudioDevice[$cfgDevice],
    "ResolvedVideo" -> resolveVideoDevice[$cfgVideoDevice]|>)

askDialog[] := Module[{q},
  q = DialogInput[DynamicModule[{text = ""},
    Column[{Style["質問を入力", Bold, 13], Spacer[5],
      InputField[Dynamic[text], String, FieldSize -> {50, 5}], Spacer[5],
      Row[{DefaultButton["送信", DialogReturn[text]], Spacer[20],
        CancelButton["キャンセル", DialogReturn[$Canceled]]}]}, Spacings -> 0.5]],
    WindowTitle -> "Ask"];
  If[q === $Canceled || !StringQ[q] || StringTrim[q] === "", Return[]]; AskQuestion[q]]

(* ============================================================ *)
(*  パレット                                                       *)
(* ============================================================ *)

SetAttributes[plButton, HoldRest];
plButton[label_String, color_, action_] :=
  Button[Style[label, Bold, 10, White],
    CompoundExpression[action,
      With[{inb = InputNotebook[]},
        If[Head[inb] === NotebookObject, SetSelectedNotebook[inb]]]],
    Appearance -> "Frameless", Background -> color,
    ImageSize -> {100, 22}, FrameMargins -> {{4, 4}, {2, 2}}, Method -> "Queued"]

ShowPalette[] := Module[{srcNB},
  If[$palette =!= None, Quiet@NotebookClose[$palette]];
  srcNB = InputNotebook[];
  If[!TrueQ[ClaudeCode`$iPaletteFallback],
    ClaudeCode`$iPaletteFallback = True;
    If[Head[srcNB] === NotebookObject,
      Quiet[ClaudeCode`iSavePaletteSettings[srcNB]]]];
  $palette = CreatePalette[
    DynamicModule[{},
    Dynamic[
    Column[{
      Style["PL Listener", Bold, 11, RGBColor[0.2, 0.3, 0.6]],
      Dynamic[Row[{
        Graphics[{If[$running, RGBColor[0.2, 0.7, 0.2], GrayLevel[0.6]], Disk[{0, 0}, 1]}, ImageSize -> 10],
        Spacer[3],
        Style[If[$running, elapsed[] <> " " <> $pSt, "Stopped"], 9,
          If[$running, RGBColor[0.2, 0.6, 0.2], GrayLevel[0.5]]]
      }], UpdateInterval -> 2],
      Dynamic[If[!$running && StringQ[$lastStartMsg] && $lastStartMsg =!= "" &&
          $lastStartMsg =!= "Started.",
        Style[$lastStartMsg, 8, RGBColor[0.7, 0.1, 0.1]], ""],
        TrackedSymbols :> {$running, $lastStartMsg}],
      Spacer[2],
      Style[" 操作", Bold, 8, GrayLevel[0.3]],
      plButton["\[RightTriangle] Start", RGBColor[0.2, 0.6, 0.3],
        StartListener["Device" -> resolveAudioDevice[$cfgDevice],
          "VideoDevice" -> resolveVideoDevice[$cfgVideoDevice],
          "CaptureInterval" -> $cfgCaptureIntv, "SlideThreshold" -> $cfgSlideThresh]],
      plButton["\[FilledSquare] Stop", RGBColor[0.7, 0.15, 0.15], StopListener[]],
      plButton["Capture", RGBColor[0.5, 0.35, 0.65], CaptureNow[]],
      plButton["? Question", RGBColor[0.3, 0.45, 0.75], askDialog[]],
      (* 回答を聞いている間は同じボタンで「回答を確定」 *)
      Dynamic[If[$vqSt === "listening",
          plButton["\[Checkmark] 回答を確定", RGBColor[0.2, 0.5, 0.3], VoiceQuestionFinish[]],
          plButton["🎤 Voice Q", RGBColor[0.75, 0.4, 0.15], voiceQuestionDialog[]]],
        TrackedSymbols :> {$vqSt}],
      Dynamic[If[StringQ[$vqStatus] && $vqStatus =!= "",
          Pane[Style[$vqStatus, 8, RGBColor[0.55, 0.3, 0.1]], 100], ""],
        TrackedSymbols :> {$vqStatus}],
      plButton["\[RightPointer] Process", RGBColor[0.55, 0.45, 0.2], processDialog[]],
      Spacer[2],
      Style[" 設定", Bold, 8, GrayLevel[0.3]],
      Dynamic[Button[
        Style["収録: " <> If[TrueQ[$ListenerAudioOnly], "音声のみ", "画像+音声"], 9, Bold,
          If[TrueQ[$ListenerAudioOnly], RGBColor[0.45, 0.3, 0.6], GrayLevel[0.2]]],
        ListenerSetAudioOnly[], Appearance -> "Frameless", Method -> "Queued"],
        TrackedSymbols :> {$ListenerAudioOnly}],
      Dynamic[Button[
        Style[If[effectiveFastMode[], "⚡ 高速", "🔧 標準"],
          9, Bold, If[effectiveFastMode[], RGBColor[0.8, 0.5, 0], GrayLevel[0.3]]],
        If[billingAllowed[], $plFastMode = !TrueQ[$plFastMode], $plFastMode = False],
        Appearance -> "Frameless"]],
      Dynamic[Button[
        Style["モデル: " <> Switch[ClaudeCode`$iPaletteModel,
          "opus", "Opus", "sonnet", "Sonnet", _, "Default"], 9, Bold, GrayLevel[0.2]],
        (ClaudeCode`$iPaletteModel = Switch[ClaudeCode`$iPaletteModel,
          "default", "opus", "opus", "sonnet", "sonnet", "default", _, "default"];
         ClaudeCode`$iPaletteEffort = "medium";
         (* claudecode 現行設計: provider/modelName を同期し
            iPaletteSyncClaudeModel[] で $ClaudeModel(tuple) を更新する。
            旧版のように $ClaudeModel を直接代入すると provider/modelName と
            不整合になるため使用しない。 *)
         ClaudeCode`$iPaletteProvider = "claudecode";
         ClaudeCode`$iPaletteModelName = Switch[ClaudeCode`$iPaletteModel,
           "opus", ClaudeCode`Private`$iModelOpus[[2]],
           "sonnet", ClaudeCode`Private`$iModelSonnet[[2]],
           _, "Automatic"];
         ClaudeCode`iPaletteSyncClaudeModel[];
         ClaudeCode`iSavePaletteSettings[InputNotebook[]]),
        Appearance -> "Frameless"]],
      Dynamic[Button[
        Style["エフォート: " <> Switch[ClaudeCode`$iPaletteEffort,
          "low", "Low", "medium", "Med", "high", "High", "max", "Max", _, "Med"],
          9, Bold, GrayLevel[0.2]],
        (If[ClaudeCode`$iPaletteModel =!= "sonnet",
          ClaudeCode`$iPaletteEffort = Switch[ClaudeCode`$iPaletteEffort,
            "low", "medium", "medium", "high", "high", "max", "max", "low", _, "medium"];
          ClaudeCode`iSavePaletteSettings[InputNotebook[]]]),
        Appearance -> "Frameless"]],
      Dynamic[Button[
        Style["課金API: " <> If[TrueQ[ClaudeCode`$iPaletteFallback], "許可", "禁止"],
          9, Bold, If[TrueQ[ClaudeCode`$iPaletteFallback],
            RGBColor[0.1, 0.5, 0.1], RGBColor[0.7, 0.1, 0.1]]],
        (ClaudeCode`$iPaletteFallback = !TrueQ[ClaudeCode`$iPaletteFallback];
         If[!TrueQ[ClaudeCode`$iPaletteFallback], $plFastMode = False];
         ClaudeCode`iSavePaletteSettings[InputNotebook[]]),
        Appearance -> "Frameless"]],
      Spacer[2],
      Button[Style["Settings...", 9, GrayLevel[0.4]], settingsDialog[],
        Appearance -> "Frameless", Method -> "Queued"],
      Button[Style["Diagnostics", 9, GrayLevel[0.5]], Print[DiagState[]],
        Appearance -> "Frameless"]
    }, Alignment -> Center, Spacings -> 0],
    TrackedSymbols :> {$running, $plFastMode,
      ClaudeCode`$iPaletteModel,
      ClaudeCode`$iPaletteEffort,
      ClaudeCode`$iPaletteFallback}
    ]],
    WindowTitle -> "Listener", WindowSize -> {105, All},
    WindowFloating -> True, WindowClickSelect -> False,
    WindowMargins -> {{Automatic, 4}, {Automatic, 4}}, Saveable -> False]]

(* 収録中の切り替えは $vidDev の付け外しだけで済む (tickVideo/captureFrame は
   $vidDev === None なら何もしない)。画像へ戻すときは差分判定を初期化する。 *)
ListenerSetAudioOnly[] := ListenerSetAudioOnly[!TrueQ[$ListenerAudioOnly]]
ListenerSetAudioOnly[b : (True | False)] := Module[{vd},
  $ListenerAudioOnly = b;
  If[!$running, Return[If[b, "音声のみ", "画像+音声"]]];
  If[b,
    $vidDev = None,
    vd = If[StringQ[$vidDevSaved], $vidDevSaved, resolveVideoDevice[$cfgVideoDevice]];
    $vidDevSaved = vd; $vidDev = vd;
    $prevFrameImg = None; $lastCapTime = None];
  wr[Cell[ts[] <> " - 収録: " <> Which[b, "音声のみ", $vidDev =!= None, "画像+音声",
      True, "画像+音声 (映像デバイスが見つからないため音声のみ)"],
    "Text", FontColor -> GrayLevel[0.45], FontSize -> 10]];
  If[b, "音声のみ", If[$vidDev =!= None, "画像+音声", "映像デバイスなし"]]]

ListenerStatus[] := If[$running, "Recording [" <> elapsed[] <> "]", "Stopped"]
ListenerRunningQ[] := $running

End[];
EndPackage[];

AddToPalettesMenu[paletteData : {{_String, _String} ..}] :=
  Module[{itemList, dummyFunction, tempFunction, temp},
    SetAttributes[FrontEnd`AddMenuCommands, HoldRest];
    MathLink`CallFrontEnd[FrontEnd`ResetMenusPacket[{Automatic}]];
    itemList = Item[First[#],
        FrontEnd`KernelExecute[{EvaluatePacket[dummyFunction@Last[#]]}],
        FrontEnd`MenuEvaluator -> Automatic] & /@ paletteData;
    temp = Function[x,
        tempFunction[{FrontEnd`AddMenuCommands["MenuListPalettesMenu",
          x]}]][itemList] /. dummyFunction -> ToExpression;
    temp /. tempFunction -> FrontEndExecute];

AddToPalettesMenu[{{"Presentation Listener",
  "Needs[\"PresentationListener`\"]; PresentationListener`ShowPalette[]"}}];
