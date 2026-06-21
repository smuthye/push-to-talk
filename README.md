# Push-to-Talk: Local Voice Typing for Mac

Talk to your Mac and have your words instantly typed wherever your cursor is —
**no typing, no internet, no cloud.** Press a hotkey, speak, press it again, and
your spoken words appear as text in any app (email, Notes, Slack, a document,
anything).

Everything runs **100% on your own Mac**. Your voice never leaves your computer.

---

## What it does

1. You press **Ctrl + Space**. A small popup appears showing it's recording.
2. You speak normally.
3. You press **Ctrl + Space** (or **Esc**) to stop.
4. A second or two later, your words are automatically typed into whatever you
   were clicked into.

That's it. It's like dictation, but private and offline.

## Why you might want this

- **Private:** Audio is transcribed on your Mac. Nothing is sent to any company.
- **Free:** No subscriptions, no per-minute charges.
- **Works offline:** Once installed, no internet needed.
- **Works everywhere:** Any text field in any app.

---

## What you need before starting

- A Mac (Apple Silicon — M1/M2/M3/M4 — or Intel), running macOS 13 (Ventura) or newer
- About **2 GB** of free disk space
- An internet connection **for the installation only** (to download the software)
- About 10–15 minutes

You do **not** need to be technical. The installer does the hard work for you.

---

## How to install (the easy way)

The whole thing installs with a single script.

### Step 1 — Open the Terminal app

Press **Cmd + Space**, type **Terminal**, and press Enter. A window with a text
prompt opens. Don't worry — you'll only copy and paste a couple of lines.

### Step 2 — Download this project

In the Terminal window, copy and paste the line below, then press Enter:

```bash
cd ~/Downloads && git clone https://github.com/smuthye/Push-to-Talk.git && cd Push-to-Talk
```

> If your Mac says `git` isn't installed, it will offer to install it — click
> **Install** and wait, then run the line above again.

### Step 3 — Run the installer

Copy and paste these two lines, pressing Enter after each:

```bash
chmod +x install_ptt.sh
./install_ptt.sh
```

The installer will automatically:

- Detect whether your Mac is Apple Silicon or Intel
- Install the voice-recognition software (whisper.cpp), the microphone tool
  (ffmpeg), and the hotkey app (Hammerspoon)
- Download the AI model that turns speech into text
- Set everything up with the **Ctrl + Space** shortcut

This step can take several minutes. It's normal to see a lot of text scroll by.

### Step 4 — Grant two permissions

For your safety, macOS will ask permission before any app can use your keyboard
and microphone. You'll need to allow **two** things (the installer prints
reminders at the end):

1. **Accessibility** — lets the hotkey work.
   System Settings → Privacy & Security → **Accessibility** → turn on
   **Hammerspoon**.
2. **Microphone** — lets it hear you.
   System Settings → Privacy & Security → **Microphone** → turn on
   **Hammerspoon**.

### Step 5 — Try it

1. Open any app with a text box (try the Notes app).
2. Click where you'd like the text to go.
3. Press **Ctrl + Space** — a popup says "Recording…"
4. Say a sentence.
5. Press **Ctrl + Space** (or **Esc**).
6. Your words appear as typed text. 🎉

---

## How to use it day to day

| Action | What to press |
|--------|----------------|
| Start talking | **Ctrl + Space** |
| Stop and insert text | **Ctrl + Space** or **Esc** |

Tip: Keep recordings short — a sentence or a paragraph at a time works best.

---

## Common questions

**Does this send my voice to the internet?**
No. All transcription happens on your Mac. Nothing is uploaded.

**Is it accurate?**
It uses OpenAI's Whisper "small" model by default, which is good for everyday
speech. You can switch to a larger, more accurate model later (see the full guide).

**It didn't type anything — what now?**
Most often it's a permission that didn't get turned on (see Step 4), or the
microphone is muted. The full guide has a Troubleshooting section that walks
through fixes.

**How do I remove it?**
The full guide has an "Uninstalling / Cleanup" section that removes everything
cleanly.

---

## Full technical guide

For a detailed, step-by-step manual install, customization (different hotkeys,
larger models, Bluetooth microphones), troubleshooting, and how it works under
the hood, see:

📄 **[push_to_talk_installation_guide.md](push_to_talk_installation_guide.md)**

---

## How it works (in one picture)

```
You press Ctrl+Space  ──►  Mac records your voice  ──►  You press Ctrl+Space/Esc
                                                                  │
                                                                  ▼
   Text is typed where  ◄──  Whisper AI turns the   ◄──  Recording stops
   your cursor is             audio into text
```

**Built with:** [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (local AI
transcription) · [ffmpeg](https://ffmpeg.org/) (microphone capture) ·
[Hammerspoon](https://www.hammerspoon.org/) (hotkey automation).

---

## License

This project is licensed under the **MIT License** — you're free to use, copy,
modify, and distribute it, including for commercial purposes, as long as the
original copyright and license notice are included. It comes with no warranty.

See the [LICENSE](LICENSE) file for the full text.

> Note: the tools this project builds on (whisper.cpp, ffmpeg, Hammerspoon) are
> distributed under their own respective licenses.
