# Push-To-Talk (PTT) Local Transcription — macOS Installation Guide

A complete, step-by-step guide to set up a local push-to-talk voice transcription system on any Mac. Press **Ctrl+Space** to start recording, then press **Ctrl+Space or Esc** to stop — the transcript is automatically pasted wherever your cursor is.

**Stack:** whisper.cpp (local AI transcription) + ffmpeg (microphone capture) + Hammerspoon (hotkey automation)

---

## Quick Install (One-Shot Script)

For automated installation without manual interaction (aside from macOS permission prompts):

```bash
chmod +x install_ptt.sh
./install_ptt.sh
```

The script auto-detects your architecture (Apple Silicon/Intel), installs all dependencies, builds whisper.cpp, downloads the model, creates PTT scripts with correct paths, installs Hammerspoon, and configures the hotkey (Ctrl+Space to start; Ctrl+Space or Esc to stop). It appends to your existing `init.lua` if one exists.

After running, you only need to manually grant two permissions (Accessibility + Microphone) — see the script's output for instructions.

The rest of this guide covers the manual step-by-step process for understanding, customization, or troubleshooting.

---

## Prerequisites

- macOS 13+ (Ventura or later recommended)
- Apple Silicon (M-series) or Intel Mac
- Homebrew installed (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`)
- Terminal access
- ~2 GB free disk space (for whisper model + build artifacts)
- Xcode Command Line Tools: `xcode-select --install`

---

## Platform Detection — Apple Silicon vs. Intel

Homebrew installs to different paths depending on architecture. Determine yours first:

```bash
which brew
```

| Architecture | Homebrew path | ffmpeg path |
|-------------|---------------|-------------|
| Apple Silicon (M1/M2/M3/M4) | `/opt/homebrew/bin/brew` | `/opt/homebrew/bin/ffmpeg` |
| Intel (x86_64) | `/usr/local/bin/brew` | `/usr/local/bin/ffmpeg` |

**Use the correct ffmpeg path throughout this guide.** All examples below use the Apple Silicon path. Intel users: substitute `/usr/local/bin/ffmpeg` wherever you see `/opt/homebrew/bin/ffmpeg`.

---

## Step 1 — Install System Dependencies

```bash
brew install git cmake pkg-config libsndfile ffmpeg
```

| Package | Purpose |
|---------|---------|
| ffmpeg | Captures microphone audio via macOS AVFoundation |
| git | Clones whisper.cpp repository |
| cmake | Builds whisper.cpp from source |
| libsndfile | Audio I/O support |

---

## Step 2 — Build whisper.cpp

```bash
cd ~
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
cmake -B build
cmake --build build -j --config Release
```

**Verify the build succeeded:**

```bash
ls -l ~/whisper.cpp/build/bin/whisper-cli
```

You should see the `whisper-cli` binary. If cmake fails:

- Ensure Xcode Command Line Tools are installed: `xcode-select --install`
- On Intel Macs, you may need: `cmake -B build -DCMAKE_OSX_ARCHITECTURES=x86_64`

**Pin to a known-good version (optional but recommended):**

```bash
cd ~/whisper.cpp
git tag | tail -5          # see recent tags
git checkout v1.8.4        # pin to a stable release
cmake -B build && cmake --build build -j --config Release
```

This prevents a future `git pull` from breaking your build.

---

## Step 3 — Download a Whisper Model

```bash
cd ~/whisper.cpp
sh ./models/download-ggml-model.sh small
```

**Model options (speed vs. accuracy):**

| Model | Size | Transcription time (5s clip, M-series) | Accuracy | Recommendation |
|-------|------|----------------------------------------|----------|----------------|
| tiny | ~75 MB | ~0.2s | Lower | Testing only |
| small | ~466 MB | ~0.6s | Good | **Default choice** |
| medium | ~1.5 GB | ~2s | Better | If small isn't accurate enough |
| large | ~3 GB | ~5s | Best | Not recommended for PTT (too slow) |

Start with `small` — it provides good accuracy with fast transcription on Apple Silicon.

**Verify model downloaded:**

```bash
ls -lh ~/whisper.cpp/models/ggml-small.bin
```

---

## Step 4 — Identify Your Microphone Device Index

```bash
$(which ffmpeg) -f avfoundation -list_devices true -i ""
```

Look for the **AVFoundation audio devices** section. Note the index number next to your microphone. Example output:

```
[AVFoundation indev] AVFoundation audio devices:
[AVFoundation indev] [0] External Microphone
[AVFoundation indev] [1] MacBook Pro Microphone
[AVFoundation indev] [2] Microsoft Teams Audio
[AVFoundation indev] [3] ZoomAudioDevice
```

In this example, MacBook Pro Microphone is `:1`. You'll use this value in the next step.

**Which device to choose:**
- For built-in mic: use the "MacBook Pro Microphone" index
- For Bluetooth headset: use the device name shown (see [Bluetooth & External Microphones](#bluetooth--external-microphones) section below)
- Avoid virtual audio devices (Teams Audio, ZoomAudioDevice) — these only carry audio during active calls

---

## Step 5 — Create the PTT Scripts

### Create the scripts directory

```bash
mkdir -p ~/bin
```

### 5a — Start recording script: `~/bin/pi-ptt-start.sh`

Create the file with your preferred editor and paste:

```bash
#!/usr/bin/env bash
LOG="/tmp/pi_ptt_debug.log"
OUT="/tmp/pi_ptt.wav"
FFMPEG="/opt/homebrew/bin/ffmpeg"    # Intel: /usr/local/bin/ffmpeg
DEVICE=":default"                    # Uses macOS default input (or set explicit index from Step 4)
MAX_DURATION=120                     # Safety: auto-stop after 2 minutes

echo "START $(date) $$" >> "$LOG"
rm -f "$OUT"

"$FFMPEG" -y -f avfoundation -i "$DEVICE" -t "$MAX_DURATION" -ar 16000 -ac 1 -vn -f wav "$OUT" 2>>"$LOG" &
PID=$!
echo "$PID" > /tmp/pi_ptt_rec_pid
echo "FFMPEG_PID=$PID" >> "$LOG"
echo "STARTED $PID" >> "$LOG"
```

**IMPORTANT — Customize these values:**

| Variable | What to change |
|----------|---------------|
| `FFMPEG` | Output of `which ffmpeg` (Intel Macs: `/usr/local/bin/ffmpeg`) |
| `DEVICE` | `:default` uses macOS Sound settings; or set explicit index from Step 4 (e.g., `:0`, `:1`) |
| `MAX_DURATION` | Safety timeout in seconds (prevents runaway recordings if you forget to stop) |

### 5b — Stop + transcribe script: `~/bin/pi-ptt-stop-and-transcribe.sh`

```bash
#!/usr/bin/env bash
LOG="/tmp/pi_ptt_debug.log"
OUT="/tmp/pi_ptt.wav"
PIDFILE="/tmp/pi_ptt_rec_pid"
MODEL="$HOME/whisper.cpp/models/ggml-small.bin"
WHISPER_BIN="$HOME/whisper.cpp/build/bin/whisper-cli"
TRANSCRIPT="/tmp/pi_ptt_transcript.txt"

echo "STOP $(date) $$" >> "$LOG"

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    echo "KILLING $PID" >> "$LOG"
    kill -INT "$PID" 2>>"$LOG" || kill -TERM "$PID" 2>>"$LOG"
    rm -f "$PIDFILE"
    sleep 0.3
else
    echo "NO PIDFILE" >> "$LOG"
fi

if [ -f "$OUT" ]; then
    echo "OUT exists, size: $(stat -f%z "$OUT")" >> "$LOG"
else
    echo "OUT missing" >> "$LOG"
fi

if [ -x "$WHISPER_BIN" ] && [ -f "$MODEL" ]; then
    "$WHISPER_BIN" -m "$MODEL" -f "$OUT" --no-timestamps > "$TRANSCRIPT" 2>>"$LOG"
    echo "TRANSCRIBED: $(wc -c < "$TRANSCRIPT") bytes" >> "$LOG"
    sed '/^[[:space:]]*$/d' "$TRANSCRIPT" | /usr/bin/pbcopy
else
    echo "WHISPER_BIN or MODEL missing" >> "$LOG"
fi

echo "DONE $(date)" >> "$LOG"
```

**IMPORTANT — Customize if needed:**

| Variable | What to change |
|----------|---------------|
| `MODEL` | Path to your downloaded model (change `ggml-small.bin` if you chose a different model) |

### 5c — Make both scripts executable

```bash
chmod +x ~/bin/pi-ptt-start.sh ~/bin/pi-ptt-stop-and-transcribe.sh
```

---

## Step 6 — Install Hammerspoon

```bash
brew install --cask hammerspoon
```

Or download from [hammerspoon.org](https://www.hammerspoon.org/) and move to `/Applications/`.

**First launch:** Open Hammerspoon from Applications. It will request **Accessibility** permission — grant it in System Settings > Privacy & Security > Accessibility.

---

## Step 7 — Grant Microphone Permission to Hammerspoon

Hammerspoon needs microphone access because it spawns the ffmpeg recording process. To trigger the macOS permission prompt:

1. Open Hammerspoon:

```bash
open -a Hammerspoon
```

2. Create (or temporarily replace) `~/.hammerspoon/init.lua` with this test:

```lua
os.execute("/opt/homebrew/bin/ffmpeg -y -f avfoundation -i ':1' -t 1 -ar 16000 -ac 1 -vn /tmp/mic_test.wav 2>/dev/null &")
```

(Intel: change the ffmpeg path; change `:1` to your device index.)

3. Reload Hammerspoon (menu bar icon > Reload Config). macOS should prompt for Microphone permission — **grant it**.

4. Verify in **System Settings > Privacy & Security > Microphone** that Hammerspoon is listed and enabled.

**If no prompt appears:**

```bash
tccutil reset Microphone
```

Then quit and relaunch Hammerspoon, and reload config again. In rare cases a reboot is required after `tccutil reset`.

---

## Step 8 — Configure the PTT Hotkey

**If you already have a `~/.hammerspoon/init.lua`:** Append the code below to your existing config rather than replacing it. The PTT code is self-contained and won't conflict with other Hammerspoon bindings.

**If this is a fresh install:** Replace the contents of `~/.hammerspoon/init.lua` with:

```lua
local timer = require "hs.timer"
local canvas = require "hs.canvas"
local screen = require "hs.screen"
local styledtext = require "hs.styledtext"

local start_script = "/Users/YOURUSERNAME/bin/pi-ptt-start.sh"
local stop_script  = "/Users/YOURUSERNAME/bin/pi-ptt-stop-and-transcribe.sh"

local recording = false
local elapsedTimer = nil
local elapsed = 0
local pttCanvas = nil
local escapeBinding = nil

local BOX_WIDTH = 420
local BOX_PADDING = 20
local BOX_MAX_HEIGHT_RATIO = 0.6
local FONT_SIZE = 14
local CORNER_RADIUS = 12

local function createCanvas(displayText, isRecording)
    local scr = screen.primaryScreen():frame()
    local maxHeight = scr.h * BOX_MAX_HEIGHT_RATIO

    local charsPerLine = math.floor((BOX_WIDTH - BOX_PADDING * 2) / (FONT_SIZE * 0.55))
    if charsPerLine < 1 then charsPerLine = 1 end
    local lines = math.ceil(#displayText / charsPerLine)
    if lines < 1 then lines = 1 end
    local textHeight = lines * (FONT_SIZE * 1.5) + BOX_PADDING * 2

    local boxHeight = math.min(textHeight + 40, maxHeight)
    if boxHeight < 80 then boxHeight = 80 end

    local x = (scr.w - BOX_WIDTH) / 2
    local y = (scr.h - boxHeight) / 2

    local c = canvas.new({x = x, y = y, w = BOX_WIDTH, h = boxHeight})

    local bgColor = isRecording and {red = 1, green = 0.97, blue = 0.97, alpha = 0.95}
                                 or {red = 0.94, green = 1, blue = 0.94, alpha = 0.95}
    local borderColor = isRecording and {red = 0.9, green = 0.3, blue = 0.3, alpha = 1}
                                     or {red = 0.2, green = 0.7, blue = 0.3, alpha = 1}

    c:appendElements(
        {
            type = "rectangle",
            action = "fill",
            roundedRectRadii = {xRadius = CORNER_RADIUS, yRadius = CORNER_RADIUS},
            fillColor = bgColor,
        },
        {
            type = "rectangle",
            action = "stroke",
            roundedRectRadii = {xRadius = CORNER_RADIUS, yRadius = CORNER_RADIUS},
            strokeColor = borderColor,
            strokeWidth = isRecording and 2 or 1,
        },
        {
            type = "text",
            frame = {
                x = BOX_PADDING,
                y = BOX_PADDING,
                w = BOX_WIDTH - BOX_PADDING * 2,
                h = boxHeight - BOX_PADDING * 2,
            },
            text = styledtext.new(displayText, {
                font = {name = ".AppleSystemUIFont", size = FONT_SIZE},
                color = {white = 0.1, alpha = 1},
                paragraphStyle = {lineSpacing = 4},
            }),
        }
    )

    c:level(canvas.windowLevels.overlay)
    c:behavior(canvas.windowBehaviors.canJoinAllSpaces)
    return c
end

local function showCanvas(text, isRecording)
    if pttCanvas then
        pttCanvas:delete()
        pttCanvas = nil
    end
    pttCanvas = createCanvas(text, isRecording)
    pttCanvas:show()
end

local function hideCanvas()
    if pttCanvas then
        pttCanvas:delete()
        pttCanvas = nil
    end
end

local function updateRecordingDisplay()
    elapsed = elapsed + 1
    local secs = elapsed % 60
    local mins = math.floor(elapsed / 60)
    local timeStr = string.format("%d:%02d", mins, secs)
    showCanvas("Recording...  " .. timeStr, true)
end

local function readTranscript()
    local f = io.open("/tmp/pi_ptt_transcript.txt", "r")
    if not f then return "" end
    local text = f:read("*a")
    f:close()
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("\n+", " ")
    return text
end

local function startRecording()
    recording = true
    elapsed = 0
    os.execute(start_script .. " &")
    showCanvas("Recording...  0:00", true)
    elapsedTimer = timer.doEvery(1, updateRecordingDisplay)
    if escapeBinding then escapeBinding:enable() end
end

local function stopRecording()
    if escapeBinding then escapeBinding:disable() end
    recording = false
    if elapsedTimer then
        elapsedTimer:stop()
        elapsedTimer = nil
    end
    showCanvas("Transcribing...", false)
    os.execute(stop_script)
    hs.eventtap.keyStroke({"cmd"}, "v")

    local finalText = readTranscript()
    if #finalText > 0 then
        showCanvas(finalText, false)
        timer.doAfter(1, hideCanvas)
    else
        showCanvas("(no speech detected)", false)
        timer.doAfter(1, hideCanvas)
    end
end

escapeBinding = hs.hotkey.new({}, "escape", function()
    if recording then stopRecording() end
end)

hs.hotkey.bind({"ctrl"}, "space", function()
    if not recording then
        startRecording()
    else
        stopRecording()
    end
end)
```

**What this does:**
- **First Ctrl+Space:** A pink-bordered popup with light pink background appears center-screen showing "Recording... 0:00" with a live timer counting up each second. Escape becomes active as a stop trigger while recording.
- **Stop (Ctrl+Space or Esc):** Popup changes to "Transcribing...", whisper-cli processes the audio (~0.5-2s for `small` model), then a green-bordered popup with light green background displays the transcript for 1 second. The text is simultaneously auto-pasted at your cursor via Cmd+V.
- The popup dynamically grows in height as transcript length increases (capped at 60% screen height)
- Escape is only intercepted while recording — outside the recording window it behaves normally (dismissing modals, vim, IDE autocomplete, etc.)

**IMPORTANT:** Replace `YOURUSERNAME` with your actual macOS username in both script paths. Find it with: `whoami`

Reload Hammerspoon (menu bar icon > Reload Config).

---

## Step 9 — Test the Full Flow

### 9a — Quick audio quality check

Before testing the full flow, verify your mic captures clear audio:

```bash
$(which ffmpeg) -y -f avfoundation -i ":default" -t 3 -ar 16000 -ac 1 -vn /tmp/mic_check.wav 2>/dev/null
afplay /tmp/mic_check.wav    # listen — should hear your voice clearly
```

If audio is muffled, distorted, or silent, fix your mic setup (System Settings > Sound > Input) before proceeding.

### 9b — Manual script test (no Hammerspoon)

```bash
~/bin/pi-ptt-start.sh
sleep 3          # speak during these 3 seconds
~/bin/pi-ptt-stop-and-transcribe.sh
pbpaste          # should show your transcript
```

### 9c — Hammerspoon hotkey test

1. Open any text field (Notes, a text editor, a chat window)
2. Click to place your cursor where you want the text
3. Press **Ctrl+Space** — a pink-bordered popup appears showing "Recording... 0:00" with a live timer
4. Speak for a few seconds
5. Press **Ctrl+Space** or **Esc** — popup changes to "Transcribing...", then a green-bordered popup shows your transcript
6. The transcript is automatically pasted at your cursor position
7. The green popup disappears after 1 second

---

## Step 10 — Verify Everything Works

Run these diagnostics if something isn't right:

```bash
# Check debug log
tail -20 /tmp/pi_ptt_debug.log

# Check wav file was created
ls -lh /tmp/pi_ptt.wav

# Check transcript
cat /tmp/pi_ptt_transcript.txt

# Check clipboard
pbpaste
```

---

## Known Limitations & Tradeoffs

| Limitation | Impact | Mitigation |
|-----------|--------|------------|
| **Blocking transcription** | Hammerspoon UI freezes during whisper processing (~0.5-2s for `small` model on short clips) | Keep recordings under 30 seconds. For longer recordings, use `medium` model only if you accept ~5s delay |
| **No streaming/interim text** | Entire recording is transcribed after stop — no real-time word display | Keep recordings short (sentence or paragraph at a time) |
| **Single clipboard** | Transcription overwrites clipboard contents | Copy important clipboard contents before recording |
| **Max recommended recording** | Beyond ~60 seconds, transcription delay becomes noticeable (3-8s with `small`) | Use the `MAX_DURATION` safety cap and keep recordings conversational-length |
| **Sleep/wake** | If Mac sleeps during recording, ffmpeg may produce corrupt audio | The `MAX_DURATION` cap prevents runaway processes; recording state resets on next toggle |

---

## Bluetooth & External Microphones

### How PTT works with Bluetooth headsets

PTT uses whatever audio device matches the `DEVICE` index in `pi-ptt-start.sh`. Bluetooth headsets appear in ffmpeg's device list **only when connected and active**.

### Finding your Bluetooth mic index

Connect your Bluetooth headset, then run:

```bash
$(which ffmpeg) -f avfoundation -list_devices true -i ""
```

Example output with AirPods connected:

```
[AVFoundation indev] AVFoundation audio devices:
[AVFoundation indev] [0] YOURUSERNAME's AirPods Pro
[AVFoundation indev] [1] MacBook Pro Microphone
[AVFoundation indev] [2] Microsoft Teams Audio
```

Here AirPods are `:0` and built-in mic is `:1`.

### Strategy A — Fixed device (simplest)

If you always use the same mic, set `DEVICE` to that index. If the device disconnects, ffmpeg will fail and the debug log will show the error.

### Strategy B — Auto-detect default input device (recommended for Bluetooth)

Replace the fixed `DEVICE` line in `~/bin/pi-ptt-start.sh` with dynamic detection:

```bash
#!/usr/bin/env bash
LOG="/tmp/pi_ptt_debug.log"
OUT="/tmp/pi_ptt.wav"
FFMPEG="/opt/homebrew/bin/ffmpeg"    # Intel: /usr/local/bin/ffmpeg
MAX_DURATION=120

# Auto-detect: use macOS default input device (index 0 in "default" context)
# This respects System Settings > Sound > Input selection
DEVICE=":default"

echo "START $(date) $$" >> "$LOG"
rm -f "$OUT"

"$FFMPEG" -y -f avfoundation -i "$DEVICE" -t "$MAX_DURATION" -ar 16000 -ac 1 -vn -f wav "$OUT" 2>>"$LOG" &
PID=$!
echo "$PID" > /tmp/pi_ptt_rec_pid
echo "FFMPEG_PID=$PID" >> "$LOG"
echo "STARTED $PID" >> "$LOG"
```

With `:default`, ffmpeg uses whatever device is selected as **Input** in System Settings > Sound. When you connect Bluetooth headphones and macOS switches input to them, PTT automatically follows. This is the recommended approach for users who switch between built-in and external microphones.

### Strategy C — Wrapper script to auto-resolve device name

If `:default` isn't supported by your ffmpeg version, use this wrapper that finds the device index by name:

```bash
#!/usr/bin/env bash
# Finds the device index for a given audio device name
# Usage: resolve with preferred device, falling back to built-in mic

FFMPEG="/opt/homebrew/bin/ffmpeg"
PREFERRED="AirPods"          # partial match on device name
FALLBACK="MacBook Pro Microphone"

get_device_index() {
    local name="$1"
    "$FFMPEG" -f avfoundation -list_devices true -i "" 2>&1 \
        | grep -i "$name" \
        | grep -oE '\[([0-9]+)\]' \
        | head -1 \
        | tr -d '[]'
}

INDEX=$(get_device_index "$PREFERRED")
if [ -z "$INDEX" ]; then
    INDEX=$(get_device_index "$FALLBACK")
fi

if [ -z "$INDEX" ]; then
    echo "ERROR: No audio device found matching '$PREFERRED' or '$FALLBACK'" >> /tmp/pi_ptt_debug.log
    exit 1
fi

echo ":$INDEX"
```

Save this as `~/bin/pi-ptt-resolve-device.sh`, make it executable, then modify `pi-ptt-start.sh`:

```bash
DEVICE=$(~/bin/pi-ptt-resolve-device.sh)
```

### Bluetooth connection timing

Bluetooth devices may take 1-2 seconds to appear after connection. If PTT starts recording before the device is ready, you'll get silence or an error.

**Workaround:** Wait until you hear your Bluetooth device's "connected" chime before pressing Ctrl+Space.

### Switching between mics without editing scripts

If using Strategy A (fixed index), you need to edit `DEVICE` when switching mics. To avoid this, use Strategy B or C above, or simply set your preferred input in **System Settings > Sound > Input** — macOS will route accordingly.

### Common Bluetooth issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Silence recorded | Bluetooth mic disconnected during recording | Reconnect and re-record |
| Low quality / robotic audio | Bluetooth in HFP/SCO mode (call mode) | Close video call apps; ensure device is in A2DP mode by playing media first |
| Device not listed | Not connected or not paired | Pair in System Settings > Bluetooth |
| Wrong device captured | Index shifted because a device disconnected | Re-run device list (Step 4), update `DEVICE` |

---

## Customization Options

### Change the hotkey

Edit `~/.hammerspoon/init.lua`. Modifier options: `ctrl`, `alt`, `cmd`, `shift`.

```lua
-- Example: Alt+Space
hs.hotkey.bind({"alt"}, "space", function()
```

**Note:** `cmd+space` conflicts with Spotlight. Disable Spotlight's shortcut first (System Settings > Keyboard > Keyboard Shortcuts > Spotlight) if you want to use it.

### Change the whisper model

Edit `~/bin/pi-ptt-stop-and-transcribe.sh` and change the `MODEL` variable:

```bash
MODEL="$HOME/whisper.cpp/models/ggml-medium.bin"  # better accuracy, slower
```

Download additional models:

```bash
cd ~/whisper.cpp
sh ./models/download-ggml-model.sh medium
```

### Auto-start Hammerspoon on login

System Settings > General > Login Items > add Hammerspoon.

### Disable auto-paste (clipboard-only mode)

If you prefer to manually paste (Cmd+V) rather than auto-paste, remove this line from `init.lua`:

```lua
hs.eventtap.keyStroke({"cmd"}, "v")
```

---

## Troubleshooting

### Problem: "REC" shows but no transcript after stop

**Check the debug log:**

```bash
tail -30 /tmp/pi_ptt_debug.log
```

**Common causes:**
- Wrong device index → re-run Step 4 and update `DEVICE` in `pi-ptt-start.sh`
- ffmpeg path wrong → run `which ffmpeg` and update `FFMPEG` in `pi-ptt-start.sh`
- Microphone permission not granted → check System Settings > Privacy & Security > Microphone

### Problem: Hammerspoon hotkey doesn't respond

1. Verify Accessibility permission: System Settings > Privacy & Security > Accessibility > Hammerspoon (enabled)
2. Check Hammerspoon Console for errors: menu bar icon > Open Console
3. Reload config: menu bar icon > Reload Config

### Problem: Transcript is empty or garbage

- Ensure wav file has reasonable size: `ls -lh /tmp/pi_ptt.wav` (should be >10 KB for a few seconds)
- Test whisper manually: `~/whisper.cpp/build/bin/whisper-cli -m ~/whisper.cpp/models/ggml-small.bin -f /tmp/pi_ptt.wav --no-timestamps`
- Try a larger model for better accuracy

### Problem: Hammerspoon hangs or freezes

Force kill and relaunch:

```bash
pkill -9 Hammerspoon
open -a Hammerspoon
```

**Why it might hang:**
- Long recording + transcription blocking the main thread. Keep recordings under 30s with `small` model.
- If it keeps hanging, ensure your `init.lua` uses `os.execute` (not `hs.task`) — the version in Step 8 above is the stable implementation.

### Problem: ffmpeg records silence (wav file tiny/empty)

- Wrong device index — re-run `$(which ffmpeg) -f avfoundation -list_devices true -i ""`
- Microphone muted in System Settings > Sound > Input
- Another app has exclusive mic access — close video call apps and retry
- Bluetooth device disconnected mid-recording

### Problem: Ctrl+Space conflicts with another app

Some apps (VS Code, IntelliJ, etc.) intercept Ctrl+Space for autocomplete. Options:
- Use a different hotkey (e.g., `{"ctrl", "alt"}, "space"`)
- Disable the conflicting binding in that app's settings
- Only use PTT when the cursor is outside those apps

### Problem: Auto-paste goes to wrong window

`hs.eventtap.keyStroke({"cmd"}, "v")` pastes into whichever window has focus when transcription completes. If you switch windows during transcription, the paste goes to the new window. Solution: stay in the target window until you see the green popup.

---

## Uninstalling / Cleanup

To completely remove the PTT system:

```bash
# Remove scripts
rm -f ~/bin/pi-ptt-start.sh ~/bin/pi-ptt-stop-and-transcribe.sh
rm -f ~/bin/pi-ptt-resolve-device.sh

# Remove temp files
rm -f /tmp/pi_ptt_debug.log /tmp/pi_ptt.wav /tmp/pi_ptt_transcript.txt /tmp/pi_ptt_rec_pid

# Remove whisper.cpp (optional — large)
rm -rf ~/whisper.cpp

# Remove Hammerspoon config (or just remove the PTT section if you have other bindings)
rm -f ~/.hammerspoon/init.lua

# Uninstall Hammerspoon
brew uninstall --cask hammerspoon

# Uninstall ffmpeg (only if nothing else uses it)
# brew uninstall ffmpeg
```

---

## File Locations Summary

| File | Purpose |
|------|---------|
| `~/bin/pi-ptt-start.sh` | Starts ffmpeg mic recording in background |
| `~/bin/pi-ptt-stop-and-transcribe.sh` | Stops recording, runs whisper, copies to clipboard |
| `~/bin/pi-ptt-resolve-device.sh` | (Optional) Auto-resolves Bluetooth mic device index |
| `~/.hammerspoon/init.lua` | Hotkey binding (Ctrl+Space toggle + auto-paste) |
| `~/whisper.cpp/build/bin/whisper-cli` | Whisper transcription binary |
| `~/whisper.cpp/models/ggml-small.bin` | Whisper AI model |
| `/tmp/pi_ptt_debug.log` | Debug log for troubleshooting |
| `/tmp/pi_ptt.wav` | Temporary audio recording |
| `/tmp/pi_ptt_transcript.txt` | Last transcript output |
| `/tmp/pi_ptt_rec_pid` | PID file for ffmpeg process management |

---

## How It Works (Architecture)

```
Ctrl+Space (press 1)          Ctrl+Space OR Esc (stop)
       |                              |
       v                              v
  pi-ptt-start.sh              pi-ptt-stop-and-transcribe.sh
       |                              |
       v                              v
  ffmpeg records mic            kill ffmpeg (SIGINT)
  to /tmp/pi_ptt.wav                  |
  (background process,                v
   max 120s safety cap)        whisper-cli transcribes wav
       |                       (~0.5-2s for small model)
       v                              |
  [PINK POPUP]                        v
  "Recording... 0:12"          strip blank lines
  (live timer ticks)                  |
  Esc binding enabled                 v
                               pbcopy → clipboard
                                      |
                                      v
                               hs.eventtap.keyStroke Cmd+V
                                      |
                                      v
                               [GREEN POPUP]
                               shows transcript (1s)
                               then auto-hides
```

All processing is **100% local** — no audio leaves your machine. No cloud APIs, no internet required after initial setup.
