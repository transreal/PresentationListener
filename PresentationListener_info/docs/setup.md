# PresentationListener — Installation Guide

On macOS/Linux, adapt the path separators and shell commands as needed. The audio and video capture uses ffmpeg's DirectShow (`dshow`) input, so the supported environment is Windows.

---

## Requirements

| Item | Requirement |
|------|-------------|
| Mathematica | 13.0 or later |
| OS | Windows 11 |
| curl | 7.55 or later, installed on the system (used for direct calls to the OpenAI Whisper API and the Anthropic API) |
| ffmpeg | Installed on the system (used for audio and video capture, and for listing DirectShow devices) |
| claudecode | The [`claudecode`](https://github.com/transreal/claudecode) package must be installed |
| NBAccess | The [`NBAccess`](https://github.com/transreal/NBAccess) package must be installed |
| OpenAI API key | Required for Whisper transcription |

> **Checking curl:** Run `curl --version` in PowerShell and confirm that a version of 7.55 or later is printed.
> Windows 11 ships with a recent curl. The version matters because API keys are passed to curl with `-H @file` (see [API Key Setup](#api-key-setup)).

> **Checking ffmpeg:** Run `ffmpeg -version` in PowerShell. See [Installing ffmpeg](#installing-ffmpeg) below if it is not found.

---

## Dependent Packages

Install the following packages first.

- **claudecode** — Integration base for the Claude Code CLI  
  → [https://github.com/transreal/claudecode](https://github.com/transreal/claudecode)

- **NBAccess** — Notebook cell operation API. It also provides the API key store.  
  → [https://github.com/transreal/NBAccess](https://github.com/transreal/NBAccess)

- **SourceVault** (optional) — Used to persist recording notebooks and session events, and to provide the notebook template for `ListenerSummary`  
  → [https://github.com/transreal/SourceVault](https://github.com/transreal/SourceVault)

- **SourceVault_realtime** (optional) — Voice bridge used by `VoiceQuestion` (asking the presenter a question by voice). It is the same gpt-live / gpt-realtime bridge that SlideWorkflow uses.  
  → [https://github.com/transreal/SourceVault_realtime](https://github.com/transreal/SourceVault_realtime)

---

## Installation Steps

### 1. Check `$packageDirectory`

Run the following in a Mathematica notebook to check the package directory path.

```mathematica
$packageDirectory
```

If the path is not set, complete the installation of the `claudecode` package first.

### 2. Place the file

Obtain `PresentationListener.wl` from the repository and place it directly under `$packageDirectory`.

```
%USERPROFILE%\<$packageDirectory>\PresentationListener.wl
```

Do not place it in a subdirectory.

### 3. Set `$Path`

If you use `claudecode`, `$Path` is set automatically. To set it manually, run:

```mathematica
If[!MemberQ[$Path, $packageDirectory],
  AppendTo[$Path, $packageDirectory]
]
```

### 4. Load the package

```mathematica
Block[{$CharacterEncoding = "UTF-8"},
  Needs["PresentationListener`", "PresentationListener.wl"]
]
```

You can reload the package with `Get["PresentationListener.wl"]` even in the middle of a recording. The state (recording, transcript, notebook and palette) is initialized only when it has no value yet. A reload therefore swaps in the new definitions without clearing the running session.

---

## Installing ffmpeg

PresentationListener resolves the ffmpeg executable itself. It does not depend only on `PATH`, because a Mathematica session started before you installed ffmpeg (for example with winget) does not know the new `PATH`. The search order is:

1. `$FFmpegPath` (an explicit path, if you set it)
2. `ffmpeg` on `PATH`
3. Known install locations:
   - `%LOCALAPPDATA%\Microsoft\WinGet\Links\ffmpeg.exe` and the `*FFmpeg*` packages under `%LOCALAPPDATA%\Microsoft\WinGet\Packages`
   - `%USERPROFILE%\scoop\shims\ffmpeg.exe`
   - `C:\ProgramData\chocolatey\bin\ffmpeg.exe`
   - `C:\Program Files\ffmpeg\bin\ffmpeg.exe`
   - `C:\ffmpeg\bin\ffmpeg.exe`

A successful lookup is cached. A failed lookup is retried every 10 seconds, so you do not need to restart Mathematica after installing ffmpeg.

To install ffmpeg, for example with winget:

```powershell
winget install Gyan.FFmpeg
```

To point the package at a specific executable, set the path explicitly before starting the listener:

```mathematica
PresentationListener`$FFmpegPath = "C:\\tools\\ffmpeg\\bin\\ffmpeg.exe"
```

---

## API Key Setup

PresentationListener calls two external APIs directly through curl.

| API | Purpose | Key |
|-----|---------|-----|
| OpenAI Whisper | Speech recognition (required) | `"openai"` |
| Anthropic | ASR correction, commentary generation, Q&A and summaries in ⚡ fast mode | `"anthropic"` |

Both keys are read through NBAccess (`NBAccess`NBGetAPIKey`), which PresentationListener calls with `AccessLevel` 1.0. Register the keys with the `claudecode` / NBAccess key management. For the OpenAI key, set it in the system credential store:

```mathematica
SystemCredential["OPENAI_API_KEY"] = "sk-xxxxxxxxxxxxxxxxxxxxxxxx"
```

### How keys are passed to curl

The key is not placed on the curl command line, because the command line of a running process can be read by anyone through the process list. Instead, the package writes the authentication header (`Authorization: Bearer …` or `x-api-key: …`) to a temporary file and passes it with curl's `-H @file` option (curl 7.55 or later). The file is deleted as soon as the response has been read. If the header file cannot be written, the request is not started.

### Verifying the OpenAI key

`StartListener[]` reports the reason when it cannot start. The message distinguishes two cases:

- **Not registered:** "Whisper 用 OpenAI キーが未登録です" — set `SystemCredential["OPENAI_API_KEY"]`.
- **Registered but denied:** "OpenAI キーは登録済みですが取得が拒否されました" — check the `AccessLevel` in `$NBPrivacySpec`.

### Billing API approval (fast mode)

⚡ Fast mode (direct curl calls to the Anthropic API) is used only when the billing API is allowed. Otherwise the listener runs in 🔧 standard mode, which uses `ClaudeQueryAsync` with the CLI preferred.

- Approval is given once, with the **billing API: allow** setting of the claudecode palette (`ClaudeCode`$iPaletteFallback`). Per-notebook approval is not requested.
- `ShowPalette[]` turns this setting on if it is off.
- `DiagState[]` shows the current mode and whether the billing API is allowed.

### Watchdog for 🔧 standard mode

In standard mode the listener waits for the `ClaudeQueryAsync` callback. If the Claude Code job disappears without calling back (CLI timeout, empty response, usage limit), or no response arrives within the time limit, the listener gives up on that request and returns to idle, so later speech is not blocked.

- The transcript is kept. If the failure happened in ASR correction, the original text is kept as the transcript. If it happened in commentary generation, a section with the speech and slides but no commentary is written.
- A response that arrives after the listener has given up, or after the listener was stopped, is discarded and recorded in the error log.
- The time limit is `$plLLMTimeout` in seconds. With `Automatic` (the default), it is `ClaudeCode`$ClaudeTimeout` plus 60 seconds.
- `DiagState[]` shows the state `llmBusy` together with the kind and sequence number of the pending request.

---

## Verification

### Launching the palette

```mathematica
ShowPalette[]
```

If a palette window appears, the package has loaded correctly. The palette's settings section also shows which microphone and camera will be used (see [Palette microphone / camera display](#palette-microphone--camera-display)).

### Listing devices and settings

```mathematica
ListAudioDevices[]
ListVideoDevices[]
ShowSettings[]
```

`ListAudioDevices[]` and `ListVideoDevices[]` list the DirectShow audio and video devices that ffmpeg returns. Use `ShowSettings[]` to choose the microphone and camera, and to switch between recording images + audio and audio only. When the list is empty, the message explains why (ffmpeg not found, or ffmpeg returned no dshow devices).

### Minimal operation test

```mathematica
(* Start the listener and stop it right away *)
StartListener[]
StopListener[]
```

If both calls finish without errors, the basic setup is complete. When `StartListener` fails, the reason is stored in `$lastStartMsg`, and the palette shows it in red.

### Common `StartListener` options

```mathematica
StartListener[
  "Device" -> Automatic,            (* audio device; Automatic uses the ShowSettings/palette setting *)
  "VideoDevice" -> Automatic,       (* video device; None disables slide capture *)
  "Language" -> Automatic,          (* language of the talk; Automatic = Whisper auto-detects *)
  "OutputLanguage" -> Automatic,    (* language of titles/commentary/Q&A; Automatic = $Language *)
  "AudioOnly" -> Automatic,         (* True = audio only (no camera); False = images + audio; Automatic = keep $ListenerAudioOnly *)
  "NotebookFolder" -> Automatic     (* where the SourceVault notebook is saved *)
]
```

- **`"Language"`** is the language of the talk. It can be a language name such as `"English"` or `"Japanese"`, or a two- or three-letter ISO code. With `Automatic`, no `language` parameter is sent and Whisper detects the language. The default is `Automatic`.
- **`"OutputLanguage"`** is the language of titles, commentary and Q&A answers. With `Automatic`, it uses `$Language`. If the speech is in a different language, a translation of it is added to the commentary at no extra API call.
- **`"AudioOnly"`** selects audio-only recording. With `True`, the camera is not opened and only the audio is recorded and processed. With `False`, images and audio are recorded. With `Automatic` (the default), the current value of `$ListenerAudioOnly` is kept. See [Audio-only recording](#audio-only-recording).
- **`"NotebookFolder"`** is where the new notebook is saved as `yyyymmdd-<title>-presentation.nb` once its title is known. With `Automatic`, the folder is resolved as described in [Notebook save folder](#notebook-save-folder).

For the other options (`"ChunkDuration"`, `"MinParagraphLength"`, `"CaptureInterval"`, `"SlideThreshold"`, `"SourceVaultSync"`, `"AutoCropSlide"`, `"SlideMaxWidth"`) the defaults work without changes.

---

## Notebook save folder

The first folder in the following list that exists is used to save the recording notebook:

1. `"NotebookFolder"` (the `StartListener` option)
2. `SourceVault`$SourceVaultDefaultNotebookFolder`
3. `$onWork`
4. The folder where a presentation notebook was last saved in this kernel
5. `~/Dropbox/On Work`
6. `$packageDirectory`
7. `$UserDocumentsDirectory`

The later candidates are a safety net. If `$onWork` and `$packageDirectory` become unresolvable in the middle of a talk, the notebook is still saved. The notebook records which folder was used.

If no candidate exists, the notebook is not saved and a warning is written to the notebook. The warning is shown **once per recording**, not once per section, and saving is retried at the next section.

---

## Palette microphone / camera display

To avoid starting a recording with the wrong input device, the palette's settings section shows the input devices that are currently in effect, as two lines: **マイク:** (microphone) and **カメラ:** (camera).

- **While stopped**, each line shows the device resolved from the `ShowSettings[]` choice (`$cfgDevice` / `$cfgVideoDevice`).
- **While recording**, each line shows the device that is actually open (the audio device, and the video device).
- The device ID (DirectShow alternative name such as `@device_pnp_...`, or the display name) is converted to a display name using the device list cache. If the ID is not in the list, the ID itself is shown. The tooltip shows the ID.
- Clicking a line opens the Settings dialog.

Suffixes and special states:

| Display | Meaning |
|---------|---------|
| `<name> (既定)` | The microphone setting is `Automatic`, so the default microphone is used |
| `<name> (自動)` | The camera setting is `Automatic`, so the camera is chosen automatically |
| `停止 (音声のみ)` | The camera is not used because `$ListenerAudioOnly` is `True` |
| `なし` | No camera is set |
| `未検出` (red) | The device could not be resolved or was not found |
| `ffmpeg なし` | ffmpeg was not found, so devices cannot be listed |

Resolving devices calls ffmpeg (`-list_devices`) and PowerShell (for the default microphone), so it is not done inside the palette's `Dynamic`. The result is stored in `$plDevLabels` (rebuilt by `plRefreshDeviceLabels[]`) only when `ShowPalette[]` opens the palette and when you press OK in Settings. If you plug in or remove a device while the palette is open, reopen it with `ShowPalette[]` or press OK in Settings to refresh the display.

---

## Audio-only recording

By default the listener records audio and also captures slide images from a webcam. If you do not need images, or no camera is connected, you can record audio only.

- **`$ListenerAudioOnly`** — when `True`, the webcam is not used and only audio is recorded and processed. The default is `False` (images + audio).
- **`StartListener["AudioOnly" -> True]`** sets `$ListenerAudioOnly` at start. The video device that was resolved is remembered, so you can switch back to images + audio later in the same session.
- **`ListenerSetAudioOnly[True | False]`** switches between audio-only and images + audio. It also works while recording; the change takes effect from the next capture. When switching back to images, the slide-difference detection is reset.
- **`ListenerSetAudioOnly[]`** with no argument toggles the current mode.
- The palette **Settings** section has a **Recording: images + audio / audio only** toggle that does the same thing. While audio only is on, the camera line of the palette shows `停止 (音声のみ)`.

```mathematica
ListenerSetAudioOnly[True]    (* audio only *)
ListenerSetAudioOnly[False]   (* images + audio *)
ListenerSetAudioOnly[]        (* toggle *)
```

If no video device is found, the listener runs audio only. Switching to images + audio then reports that there is no video device. `DiagState[]` shows the video state as `ON`, `OFF 音声のみ` (audio only), or `OFF`. It also prints the configured devices (`cfgDevice` / `cfgVideoDevice`) and the names shown on the palette (`paletteDevices`), which helps when the palette display does not match what you expect.

---

## Asking questions about the talk

`AskQuestion["..."]` asks the LLM a question about the talk recorded so far, and writes the answer to the notebook.

- To refer to a section, write its number in the question, for example `#3`.
- If the question has no number, the sections are ranked by word overlap between the question and each section's speech, commentary and translation. Words that appear in every section count less. The slides of the top two sections are attached to the question, so questions such as "reproduce the figure" can be answered from the slide. If no section matches, the slides of the last section are attached.
- Answers are rendered as notebook cells: TeX math is typeset, `**bold**` and bullet lists are formatted. When you ask for a calculation, plot or reproduction of a figure, the answer includes self-contained Wolfram Language code in an Input cell that you can evaluate with Shift+Enter. Any assumption the code makes about values not readable from the slides or speech is stated both in a code comment and in the text.
- In ⚡ fast mode the question is sent directly to the Anthropic API. In 🔧 standard mode it uses `ClaudeQueryAsync` (CLI preferred). If a direct API request returns no usable response, the error is written to the error log instead of the notebook.

The same Markdown/TeX rendering is used for the commentary sections.

---

## Voice Question (optional)

`VoiceQuestion` reads a question aloud to the presenter, collects the spoken answer as text, and writes both to the notebook. It requires SourceVault and SourceVault_realtime to be installed and loaded. The palette shows a **Voice Q** button, which turns into a **Confirm answer** button while the answer is being heard.

- The question is first translated into the presenter's language by an LLM, so the voice model only reads it aloud. The presenter's language is taken from `"Language"` when it is set. Otherwise it is guessed from the recent transcript. If neither gives a clue, the question is read as written.
- The voice model is chosen from `$VoiceQuestionModel`, then SlideWorkflow's voice model, and otherwise defaults to `gpt-live-1`.
- The answer ends after `$VoiceQuestionSilence` seconds of silence, or when you press **Confirm answer** (`VoiceQuestionFinish[]`).
- The original answer is written first, and the answer translated into the output language follows. If the translation does not arrive (the job vanished or timed out), the original text is kept as it is.
- The questions and the presenter's answers are also passed to `ListenerSummary`.

---

## Talk summary (`ListenerSummary`)

`ListenerSummary[]` creates a summary of the talk so far in a separate notebook. It uses the transcript and commentary, the speech that does not have commentary yet, and the answers to voice questions.

- The LLM produces three parts: a **summary** (3–6 sentences), **key points** (3–7 items, each with its detail), and **open questions** (0–6 items): points that cannot be understood without more information, such as undefined terms, skipped steps of an argument, claims without conditions or grounds, and inaudible or ambiguous passages.
- The summary notebook is created from the SourceVault notebook template. There is **one summary notebook per recording**. Each time you run it, a section headed with the elapsed time (`mm:ss`) is appended and earlier sections remain.
- If the recording notebook is already saved, the summary notebook is saved in the same folder as `…-summary.nb` and registered.
- In ⚡ fast mode the summary is requested directly through curl, using `$ListenerSummaryModel`. In 🔧 standard mode it uses `ClaudeQueryAsync`. Neither blocks the recording.
- A summary request that does not return for a long time (600 seconds) is discarded, so you can start it again.

---

## SourceVault Integration (optional)

If the SourceVault package is installed, recording session notes are saved automatically.
The integration is detected automatically, so no additional setup is needed. When SourceVault is not loaded, PresentationListener works standalone.

- New notebooks are created from the SourceVault template (`SourceVaultNewNotebook`). Without SourceVault, a plain notebook window is created.
- The transcript, commentary and questions are ingested as session events. Turn this off with `"SourceVaultSync" -> False`.
- When the notebook is saved, its path is recorded as a session event, so the notebook can be reached from the session.

```mathematica
(* Check the current SourceVault session *)
ListenerSourceVaultSession[]
```

---

## Troubleshooting

| Symptom | Remedy |
|---------|--------|
| "File not found" error when running `Needs` | Check that the `.wl` file exists in `$packageDirectory` |
| `StartListener` reports that ffmpeg was not found | Install ffmpeg (see [Installing ffmpeg](#installing-ffmpeg)), or set `PresentationListener`$FFmpegPath`. No restart is needed after installing |
| `StartListener` reports that the OpenAI key is not registered | Set `SystemCredential["OPENAI_API_KEY"]` |
| The OpenAI key is registered but retrieval is denied | Check the `AccessLevel` in `$NBPrivacySpec` |
| `StartListener` cannot resolve an audio device | Select a microphone in `ShowSettings[]`, or pass `"Device" -> "<device name>"` (see `ListAudioDevices[]`) |
| The device list is empty | Check that ffmpeg is found and that a microphone is connected and enabled in Windows |
| Device names appear garbled (for example the Japanese "マイク") | The package repairs ffmpeg's UTF-8 device names automatically. Reload the package if you still see garbled names |
| The palette's microphone / camera line shows `未検出` or an old device | The display is refreshed only when the palette opens and when Settings is confirmed with OK. Reopen with `ShowPalette[]` or press OK in `ShowSettings[]`. Check `DiagState[]` (`cfgDevice`, `cfgVideoDevice`, `paletteDevices`) |
| The palette's microphone / camera line shows `ffmpeg なし` | ffmpeg was not found. Install it (see [Installing ffmpeg](#installing-ffmpeg)) and reopen the palette |
| Whisper or the Anthropic API requests do not start (no transcription at all) | The temporary authentication header file could not be written, or curl is older than 7.55 (`-H @file` is unsupported). Check `curl --version` and that the temporary directory is writable |
| Only 🔧 standard mode is used, not ⚡ fast mode | Allow the billing API in the palette (`ShowPalette[]`), and check the Anthropic key |
| In 🔧 standard mode the commentary stops appearing and the state stays `llmBusy` | The watchdog gives up on a request when the Claude Code job disappears or `$plLLMTimeout` passes, then returns to idle. The transcript is kept. Check `DiagState[]` and the error log for the reason, or adjust `$plLLMTimeout` |
| A response written "after giving up" is missing from the notebook | A response that arrives after the watchdog gave up, or after `StopListener[]`, is discarded on purpose. Its entry remains in the error log |
| The notebook was not saved ("保存先フォルダを解決できませんでした") | None of the candidate folders exists. Pass `"NotebookFolder" -> "<existing folder>"` to `StartListener`, or define `$onWork` (see [Notebook save folder](#notebook-save-folder)). The warning appears once per recording and saving is retried at the next section |
| The commentary or translation is not in the expected language | Set `"Language"` (language of the talk) and `"OutputLanguage"` (language of the output) explicitly |
| An `AskQuestion` answer does not mention the figure you asked about | Put the section number in the question (for example `#3`), so that section's slides are attached |
| No slide images are captured | Check whether `$ListenerAudioOnly` is `True` (switch with `ListenerSetAudioOnly[False]` or the palette toggle), and that a camera is selected in `ShowSettings[]` |
| `ListenerSetAudioOnly[False]` reports "No video device." | No camera was resolved. Connect one and select it in `ShowSettings[]`, then restart the listener |
| curl not found error | Run `curl --version` in PowerShell and check that curl is on the path |
| The palette does not appear | Check that `NBAccess` loads correctly with `Needs["NBAccess`"]` |
| `VoiceQuestion` does not work | Check that SourceVault and SourceVault_realtime are installed and loaded |
| `ListenerSummary` does not return | A request that has not returned for 600 seconds is discarded. Run it again. Check the billing API setting if you expected ⚡ fast mode |

---

## Related Links

- Repository: [https://github.com/transreal/PresentationListener](https://github.com/transreal/PresentationListener)
- claudecode: [https://github.com/transreal/claudecode](https://github.com/transreal/claudecode)
- NBAccess: [https://github.com/transreal/NBAccess](https://github.com/transreal/NBAccess)
- SourceVault: [https://github.com/transreal/SourceVault](https://github.com/transreal/SourceVault)
- SourceVault_realtime: [https://github.com/transreal/SourceVault_realtime](https://github.com/transreal/SourceVault_realtime)