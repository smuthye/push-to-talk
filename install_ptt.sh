#!/usr/bin/env bash
set -euo pipefail

#####################################################################
# Push-To-Talk (PTT) Local Transcription — One-Shot Installer
#
# Installs everything needed for local voice-to-text on macOS:
#   - Homebrew dependencies (ffmpeg, cmake, etc.)
#   - whisper.cpp (builds from source)
#   - Whisper "small" model
#   - PTT start/stop scripts
#   - Hammerspoon + init.lua hotkey config
#
# Usage:
#   chmod +x install_ptt.sh
#   ./install_ptt.sh
#
# After running:
#   1. Open Hammerspoon (it will ask for Accessibility permission — grant it)
#   2. Reload Hammerspoon config (menu bar > Reload Config)
#   3. Grant Microphone permission when prompted
#   4. Press Ctrl+Space to record; Ctrl+Space or Esc to stop & paste
#
# Requirements:
#   - macOS 13+ (Ventura or later)
#   - Internet connection (for downloads)
#   - ~2 GB free disk space
#####################################################################

# ── Colors for output ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ── Detect environment ──
USERNAME=$(whoami)
HOME_DIR=$(eval echo ~"$USERNAME")
ARCH=$(uname -m)

if [ "$ARCH" = "arm64" ]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

FFMPEG_PATH="$BREW_PREFIX/bin/ffmpeg"
WHISPER_DIR="$HOME_DIR/whisper.cpp"
MODEL_NAME="ggml-small.bin"
MODEL_PATH="$WHISPER_DIR/models/$MODEL_NAME"
WHISPER_BIN="$WHISPER_DIR/build/bin/whisper-cli"
BIN_DIR="$HOME_DIR/bin"
HAMMERSPOON_DIR="$HOME_DIR/.hammerspoon"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Push-To-Talk Local Transcription — Installer          ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  User:       $USERNAME"
echo "║  Arch:       $ARCH"
echo "║  Brew:       $BREW_PREFIX"
echo "║  ffmpeg:     $FFMPEG_PATH"
echo "║  whisper:    $WHISPER_BIN"
echo "║  Model:      $MODEL_PATH"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ══════════════════════════════════════════════════════════════════════
# Step 1: Homebrew
# ══════════════════════════════════════════════════════════════════════
log_info "Step 1/7: Checking Homebrew..."

if ! command -v brew &>/dev/null; then
    log_warn "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$($BREW_PREFIX/bin/brew shellenv)"
else
    log_ok "Homebrew found at $(which brew)"
fi

# ══════════════════════════════════════════════════════════════════════
# Step 2: System dependencies
# ══════════════════════════════════════════════════════════════════════
log_info "Step 2/7: Installing system dependencies..."

DEPS="git cmake pkg-config libsndfile ffmpeg"
for dep in $DEPS; do
    if brew list "$dep" &>/dev/null; then
        log_ok "$dep already installed"
    else
        log_info "Installing $dep..."
        brew install "$dep"
    fi
done

# Verify ffmpeg
if [ ! -x "$FFMPEG_PATH" ]; then
    FFMPEG_PATH=$(which ffmpeg)
    if [ -z "$FFMPEG_PATH" ]; then
        log_error "ffmpeg not found after installation. Aborting."
        exit 1
    fi
fi
log_ok "ffmpeg at $FFMPEG_PATH"

# ══════════════════════════════════════════════════════════════════════
# Step 3: Build whisper.cpp
# ══════════════════════════════════════════════════════════════════════
log_info "Step 3/7: Building whisper.cpp..."

if [ -x "$WHISPER_BIN" ]; then
    log_ok "whisper-cli already built at $WHISPER_BIN"
else
    if [ ! -d "$WHISPER_DIR" ]; then
        log_info "Cloning whisper.cpp..."
        git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
    fi
    cd "$WHISPER_DIR"
    log_info "Building (this may take 1-2 minutes)..."
    cmake -B build 2>&1 | tail -3
    cmake --build build -j --config Release 2>&1 | tail -3

    if [ ! -x "$WHISPER_BIN" ]; then
        log_error "Build failed. whisper-cli not found at $WHISPER_BIN"
        log_error "Try manually: cd ~/whisper.cpp && cmake -B build && cmake --build build -j"
        exit 1
    fi
    log_ok "whisper-cli built successfully"
fi

# ══════════════════════════════════════════════════════════════════════
# Step 4: Download whisper model
# ══════════════════════════════════════════════════════════════════════
log_info "Step 4/7: Downloading whisper model (small, ~466 MB)..."

if [ -f "$MODEL_PATH" ]; then
    log_ok "Model already exists at $MODEL_PATH"
else
    cd "$WHISPER_DIR"
    sh ./models/download-ggml-model.sh small
    if [ ! -f "$MODEL_PATH" ]; then
        log_error "Model download failed. Try manually:"
        log_error "  cd ~/whisper.cpp && sh ./models/download-ggml-model.sh small"
        exit 1
    fi
    log_ok "Model downloaded"
fi

# ══════════════════════════════════════════════════════════════════════
# Step 5: Create PTT scripts
# ══════════════════════════════════════════════════════════════════════
log_info "Step 5/7: Creating PTT scripts..."

mkdir -p "$BIN_DIR"

# Start script
cat > "$BIN_DIR/pi-ptt-start.sh" << 'STARTEOF'
#!/usr/bin/env bash
LOG="/tmp/pi_ptt_debug.log"
OUT="/tmp/pi_ptt.wav"
FFMPEG="__FFMPEG_PATH__"
DEVICE=":default"
MAX_DURATION=120

echo "START $(date) $$" >> "$LOG"
rm -f "$OUT"

"$FFMPEG" -y -f avfoundation -i "$DEVICE" -t "$MAX_DURATION" -ar 16000 -ac 1 -vn -f wav "$OUT" 2>>"$LOG" &
PID=$!
echo "$PID" > /tmp/pi_ptt_rec_pid
echo "FFMPEG_PID=$PID" >> "$LOG"
echo "STARTED $PID" >> "$LOG"
STARTEOF

# Stop + transcribe script
cat > "$BIN_DIR/pi-ptt-stop-and-transcribe.sh" << 'STOPEOF'
#!/usr/bin/env bash
LOG="/tmp/pi_ptt_debug.log"
OUT="/tmp/pi_ptt.wav"
PIDFILE="/tmp/pi_ptt_rec_pid"
MODEL="__MODEL_PATH__"
WHISPER_BIN="__WHISPER_BIN__"
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
STOPEOF

# Inject actual paths
sed -i '' "s|__FFMPEG_PATH__|$FFMPEG_PATH|g" "$BIN_DIR/pi-ptt-start.sh"
sed -i '' "s|__MODEL_PATH__|$MODEL_PATH|g" "$BIN_DIR/pi-ptt-stop-and-transcribe.sh"
sed -i '' "s|__WHISPER_BIN__|$WHISPER_BIN|g" "$BIN_DIR/pi-ptt-stop-and-transcribe.sh"

chmod +x "$BIN_DIR/pi-ptt-start.sh" "$BIN_DIR/pi-ptt-stop-and-transcribe.sh"

log_ok "Scripts created at $BIN_DIR/pi-ptt-start.sh and $BIN_DIR/pi-ptt-stop-and-transcribe.sh"

# ══════════════════════════════════════════════════════════════════════
# Step 6: Install Hammerspoon
# ══════════════════════════════════════════════════════════════════════
log_info "Step 6/7: Installing Hammerspoon..."

if [ -d "/Applications/Hammerspoon.app" ]; then
    log_ok "Hammerspoon already installed"
else
    brew install --cask hammerspoon
    if [ ! -d "/Applications/Hammerspoon.app" ]; then
        log_error "Hammerspoon installation failed."
        exit 1
    fi
    log_ok "Hammerspoon installed"
fi

# ══════════════════════════════════════════════════════════════════════
# Step 7: Configure Hammerspoon init.lua
# ══════════════════════════════════════════════════════════════════════
log_info "Step 7/7: Configuring Hammerspoon..."

mkdir -p "$HAMMERSPOON_DIR"

PTT_MARKER="-- PTT: Push-To-Talk Configuration"

# Check if PTT config already exists in init.lua
if [ -f "$HAMMERSPOON_DIR/init.lua" ] && grep -q "$PTT_MARKER" "$HAMMERSPOON_DIR/init.lua"; then
    log_ok "PTT config already present in init.lua"
else
    # Append (or create) PTT config
    cat >> "$HAMMERSPOON_DIR/init.lua" << LUAEOF

$PTT_MARKER
local timer = require "hs.timer"
local canvas = require "hs.canvas"
local screen = require "hs.screen"
local styledtext = require "hs.styledtext"

local ptt_start_script = "$BIN_DIR/pi-ptt-start.sh"
local ptt_stop_script  = "$BIN_DIR/pi-ptt-stop-and-transcribe.sh"

local ptt_recording = false
local ptt_elapsedTimer = nil
local ptt_elapsed = 0
local ptt_canvas = nil
local ptt_escapeBinding = nil

local PTT_BOX_WIDTH = 420
local PTT_BOX_PADDING = 20
local PTT_BOX_MAX_HEIGHT_RATIO = 0.6
local PTT_FONT_SIZE = 14
local PTT_CORNER_RADIUS = 12

local function ptt_createCanvas(displayText, isRecording)
    local scr = screen.primaryScreen():frame()
    local maxHeight = scr.h * PTT_BOX_MAX_HEIGHT_RATIO

    local charsPerLine = math.floor((PTT_BOX_WIDTH - PTT_BOX_PADDING * 2) / (PTT_FONT_SIZE * 0.55))
    if charsPerLine < 1 then charsPerLine = 1 end
    local lines = math.ceil(#displayText / charsPerLine)
    if lines < 1 then lines = 1 end
    local textHeight = lines * (PTT_FONT_SIZE * 1.5) + PTT_BOX_PADDING * 2

    local boxHeight = math.min(textHeight + 40, maxHeight)
    if boxHeight < 80 then boxHeight = 80 end

    local x = (scr.w - PTT_BOX_WIDTH) / 2
    local y = (scr.h - boxHeight) / 2

    local c = canvas.new({x = x, y = y, w = PTT_BOX_WIDTH, h = boxHeight})

    local bgColor = isRecording and {red = 1, green = 0.97, blue = 0.97, alpha = 0.95}
                                 or {red = 0.94, green = 1, blue = 0.94, alpha = 0.95}
    local borderColor = isRecording and {red = 0.9, green = 0.3, blue = 0.3, alpha = 1}
                                     or {red = 0.2, green = 0.7, blue = 0.3, alpha = 1}

    c:appendElements(
        {
            type = "rectangle",
            action = "fill",
            roundedRectRadii = {xRadius = PTT_CORNER_RADIUS, yRadius = PTT_CORNER_RADIUS},
            fillColor = bgColor,
        },
        {
            type = "rectangle",
            action = "stroke",
            roundedRectRadii = {xRadius = PTT_CORNER_RADIUS, yRadius = PTT_CORNER_RADIUS},
            strokeColor = borderColor,
            strokeWidth = isRecording and 2 or 1,
        },
        {
            type = "text",
            frame = {
                x = PTT_BOX_PADDING,
                y = PTT_BOX_PADDING,
                w = PTT_BOX_WIDTH - PTT_BOX_PADDING * 2,
                h = boxHeight - PTT_BOX_PADDING * 2,
            },
            text = styledtext.new(displayText, {
                font = {name = ".AppleSystemUIFont", size = PTT_FONT_SIZE},
                color = {white = 0.1, alpha = 1},
                paragraphStyle = {lineSpacing = 4},
            }),
        }
    )

    c:level(canvas.windowLevels.overlay)
    c:behavior(canvas.windowBehaviors.canJoinAllSpaces)
    return c
end

local function ptt_showCanvas(text, isRecording)
    if ptt_canvas then
        ptt_canvas:delete()
        ptt_canvas = nil
    end
    ptt_canvas = ptt_createCanvas(text, isRecording)
    ptt_canvas:show()
end

local function ptt_hideCanvas()
    if ptt_canvas then
        ptt_canvas:delete()
        ptt_canvas = nil
    end
end

local function ptt_updateRecordingDisplay()
    ptt_elapsed = ptt_elapsed + 1
    local secs = ptt_elapsed % 60
    local mins = math.floor(ptt_elapsed / 60)
    local timeStr = string.format("%d:%02d", mins, secs)
    ptt_showCanvas("Recording...  " .. timeStr, true)
end

local function ptt_readTranscript()
    local f = io.open("/tmp/pi_ptt_transcript.txt", "r")
    if not f then return "" end
    local text = f:read("*a")
    f:close()
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("\n+", " ")
    return text
end

local function ptt_startRecording()
    ptt_recording = true
    ptt_elapsed = 0
    os.execute(ptt_start_script .. " &")
    ptt_showCanvas("Recording...  0:00", true)
    ptt_elapsedTimer = timer.doEvery(1, ptt_updateRecordingDisplay)
    if ptt_escapeBinding then ptt_escapeBinding:enable() end
end

local function ptt_stopRecording()
    if ptt_escapeBinding then ptt_escapeBinding:disable() end
    ptt_recording = false
    if ptt_elapsedTimer then
        ptt_elapsedTimer:stop()
        ptt_elapsedTimer = nil
    end
    ptt_showCanvas("Transcribing...", false)
    os.execute(ptt_stop_script)
    hs.eventtap.keyStroke({"cmd"}, "v")

    local finalText = ptt_readTranscript()
    if #finalText > 0 then
        ptt_showCanvas(finalText, false)
        timer.doAfter(1, ptt_hideCanvas)
    else
        ptt_showCanvas("(no speech detected)", false)
        timer.doAfter(1, ptt_hideCanvas)
    end
end

ptt_escapeBinding = hs.hotkey.new({}, "escape", function()
    if ptt_recording then ptt_stopRecording() end
end)

hs.hotkey.bind({"ctrl"}, "space", function()
    if not ptt_recording then
        ptt_startRecording()
    else
        ptt_stopRecording()
    end
end)
LUAEOF
    log_ok "PTT config added to $HAMMERSPOON_DIR/init.lua"
fi

# ══════════════════════════════════════════════════════════════════════
# Done — Summary
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 Installation Complete!                       ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                              ║"
echo "║  Next steps (manual — requires GUI interaction):             ║"
echo "║                                                              ║"
echo "║  1. Open Hammerspoon:                                        ║"
echo "║       open -a Hammerspoon                                    ║"
echo "║                                                              ║"
echo "║  2. Grant ACCESSIBILITY permission when prompted             ║"
echo "║     (System Settings > Privacy & Security > Accessibility)   ║"
echo "║                                                              ║"
echo "║  3. Reload config: menu bar icon > Reload Config             ║"
echo "║                                                              ║"
echo "║  4. Press Ctrl+Space once — grant MICROPHONE permission      ║"
echo "║     when macOS prompts                                       ║"
echo "║                                                              ║"
echo "║  5. You're done! Ctrl+Space to record; Ctrl+Space or Esc    ║"
echo "║     to stop. Transcript auto-pastes at your cursor.          ║"
echo "║                                                              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Hotkey:     Ctrl+Space (toggle); Esc also stops recording   ║"
echo "║  Model:      small (~0.6s transcription)                     ║"
echo "║  Device:     macOS default input (follows Sound settings)    ║"
echo "║  Max rec:    120 seconds (safety cap)                        ║"
echo "║  Debug log:  /tmp/pi_ptt_debug.log                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Quick test
log_info "Running quick audio test (2 second recording)..."
"$BIN_DIR/pi-ptt-start.sh"
sleep 2
"$BIN_DIR/pi-ptt-stop-and-transcribe.sh"

if [ -f /tmp/pi_ptt_transcript.txt ] && [ -s /tmp/pi_ptt_transcript.txt ]; then
    log_ok "Audio pipeline working! Transcript: $(cat /tmp/pi_ptt_transcript.txt)"
else
    log_warn "Audio test produced no transcript. Check /tmp/pi_ptt_debug.log"
    log_warn "You may need to grant Microphone permission (Step 4 above) first."
fi

echo ""
log_info "To test manually: press Ctrl+Space, speak, press Ctrl+Space or Esc to stop."
