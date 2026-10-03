# PresentationListener — Installation Guide

On macOS/Linux, adapt the path separators and shell commands as needed. The audio and video capture uses ffmpeg's DirectShow (`dshow`) input, so the supported environment is Windows.

---

## Requirements

| Item | Requirement |
|------|-------------|
| Mathematica | 13.0 or later |
| OS | Windows 11 |
| curl | Installed on the system (used for direct calls to the OpenAI Whisper API and the Anthropic API) |
| ffmpeg | Installed on the system (used for audio and video capture, and for listing DirectShow devices) |
| claudecode | The [`claudecode`](https://github.com/transreal/claudecode) package must be installed |
| NBAccess | The [`NBAccess`](https://github.com/transreal/NBAccess) package must be installed |
| OpenAI API key | Required for Whisper transcription |

> **Checking curl:** Run `curl --version` in PowerShell and confirm that a version is printed.
> Windows 11 ships with curl.

> **Checking ffmpeg:** Run `ffmpeg -version` in PowerShell. See [Installing ffmpeg](#installing-ffmpeg) below if it is not found.

---

## Dependent Packages

Install the following packages first.

- **claudecode** — Integration base for the Claude Code CLI  
  → [https://github.com/transreal/claudecode](https://github.com/transreal/claudecode)

- **NBAccess** — Notebook cell operation API. It also provides the API key store.  
  → [https://github.com/transreal/NBAccess](https://github.com/transreal/NBAccess)

- **SourceVault** (optional) — Used to persist recording notebooks and session events  
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
| Anthropic | ASR correction and commentary generation in ⚡ fast mode | `"anthropic"` |

Both keys are read through NBAccess (`NBAccess`NBGetAPIKey`), which PresentationListener calls with `AccessLevel` 1.0. Register the keys with the `claudecode` / NBAccess key management. For the OpenAI key, set it in the system credential store:

```mathematica
SystemCredential["OPENAI_API_KEY"] = "sk-xxxxxxxxxxxxxxxxxxxxxxxx"
```

### Verifying the OpenAI key

`StartListener[]` reports the reason when it cannot start. The message distinguishes two cases:

- **Not registered:** "Whisper 用 OpenAI キーが未登録です" — set `SystemCredential["OPENAI_API_KEY"]`.
- **Registered but denied:** "OpenAI キーは登録済みですが取得が拒否されました" — check the `AccessLevel` in `$NBPrivacySpec`.

### Billing API approval (fast mode)

⚡ Fast mode (direct curl calls to the Anthropic API) is used only when the billing API is allowed. Otherwise the listener runs in 🔧 standard mode, which uses `ClaudeQueryAsync` with the CLI preferred.

- Approval is given once, with the **billing API: allow** setting of the claudecode palette (`ClaudeCode`$iPaletteFallback`). Per-notebook approval is not requested.
- `ShowPalette[]` turns this setting on if it is off.
- `DiagState[]` shows the current mode and whether the billing API is allowed.

---

## Verification

### Launching the palette

```mathematica
ShowPalette[]
```

If a palette window appears, the package has loaded correctly.

### Listing devices and settings

```mathematica
ListAudioDevices[]
ShowSettings[]
```

`ListAudioDevices[]` lists the DirectShow devices that ffmpeg returns. Use `ShowSettings[]` to choose the microphone and camera, and to switch between recording images + audio and audio only. When the list is empty, the message explains why (ffmpeg not found, or ffmpeg returned no dshow devices).

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
- **`"NotebookFolder"`** is where the new notebook is saved as `yyyymmdd-<title>-presentation.nb` once its title is known. With `Automatic`, the folder is resolved from SourceVault's default notebook folder, then `$onWork`, then `$packageDirectory`.

For the other options (`"ChunkDuration"`, `"MinParagraphLength"`, `"CaptureInterval"`, `"SlideThreshold"`, `"SourceVaultSync"`, `"AutoCropSlide"`, `"SlideMaxWidth"`) the defaults work without changes.

---

## Audio-only recording

By default the listener records audio and also captures slide images from a webcam. If you do not need images, or no camera is connected, you can record audio only.

- **`$ListenerAudioOnly`** — when `True`, the webcam is not used and only audio is recorded and processed. The default is `False` (images + audio).
- **`StartListener["AudioOnly" -> True]`** sets `$ListenerAudioOnly` at start. The video device that was resolved is remembered, so you can switch back to images + audio later in the same session.
- **`ListenerSetAudioOnly[True | False]`** switches between audio-only and images + audio. It also works while recording; the change takes effect from the next capture. When switching back to images, the slide-difference detection is reset.
- **`ListenerSetAudioOnly[]`** with no argument toggles the current mode.
- The palette **Settings** section has a **Recording: images + audio / audio only** toggle that does the same thing.

```mathematica
ListenerSetAudioOnly[True]    (* audio only *)
ListenerSetAudioOnly[False]   (* images + audio *)
ListenerSetAudioOnly[]        (* toggle *)
```

If no video device is found, the listener runs audio only. Switching to images + audio then reports that there is no video device. `DiagState[]` shows the video state as `ON`, `OFF 音声のみ` (audio only), or `OFF`.

---

## Voice Question (optional)

`VoiceQuestion` reads a question aloud to the presenter, collects the spoken answer as text, and writes both to the notebook. It requires SourceVault and SourceVault_realtime to be installed and loaded. The palette shows a **Voice Q** button, which turns into a **Confirm answer** button while the answer is being heard.

- The question is first translated into the presenter's language by an LLM, so the voice model only reads it aloud. The presenter's language is taken from `"Language"` when it is set. Otherwise it is guessed from the recent transcript. If neither gives a clue, the question is read as written.
- The voice model is chosen from `$VoiceQuestionModel`, then SlideWorkflow's voice model, and otherwise defaults to `gpt-live-1`.
- The answer ends after `$VoiceQuestionSilence` seconds of silence, or when you press **Confirm answer** (`VoiceQuestionFinish[]`).

---

## SourceVault Integration (optional)

If the SourceVault package is installed, recording session notes are saved automatically.
The integration is detected automatically, so no additional setup is needed. When SourceVault is not loaded, PresentationListener works standalone.

- New notebooks are created from the SourceVault template (`SourceVaultNewNotebook`). Without SourceVault, a plain notebook window is created.
- The transcript, commentary and questions are ingested as session events. Turn this off with `"SourceVaultSync" -> False`.

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
| Only 🔧 standard mode is used, not ⚡ fast mode | Allow the billing API in the palette (`ShowPalette[]`), and check the Anthropic key |
| The commentary or translation is not in the expected language | Set `"Language"` (language of the talk) and `"OutputLanguage"` (language of the output) explicitly |
| No slide images are captured | Check whether `$ListenerAudioOnly` is `True` (switch with `ListenerSetAudioOnly[False]` or the palette toggle), and that a camera is selected in `ShowSettings[]` |
| `ListenerSetAudioOnly[False]` reports "No video device." | No camera was resolved. Connect one and select it in `ShowSettings[]`, then restart the listener |
| curl not found error | Run `curl --version` in PowerShell and check that curl is on the path |
| The palette does not appear | Check that `NBAccess` loads correctly with `Needs["NBAccess`"]` |
| `VoiceQuestion` does not work | Check that SourceVault and SourceVault_realtime are installed and loaded |

---

## Related Links

- Repository: [https://github.com/transreal/PresentationListener](https://github.com/transreal/PresentationListener)
- claudecode: [https://github.com/transreal/claudecode](https://github.com/transreal/claudecode)
- NBAccess: [https://github.com/transreal/NBAccess](https://github.com/transreal/NBAccess)
- SourceVault: [https://github.com/transreal/SourceVault](https://github.com/transreal/SourceVault)
- SourceVault_realtime: [https://github.com/transreal/SourceVault_realtime](https://github.com/transreal/SourceVault_realtime)