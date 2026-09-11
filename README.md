# SignMasterPan

**Middle mouse button panning and a calm mouse wheel zoom for SignMaster V5.**

SignMasterPan is a small, free Windows helper that runs in the background next to the sign-making software **SignMaster V5** (FutureCorp). While SignMaster is active, you can pan the workspace by dragging with the middle mouse button, just like in most CAD and graphics programs. The mouse wheel zoom no longer jumps around.

> [!NOTE]
> **This project was created with the help of AI.** The source code, the icons and this documentation were written with [Claude Code](https://claude.com/claude-code) (Anthropic), guided and tested by a SignMaster user. The code has been tested in practice, but please review it yourself before relying on it.

---

## Why this tool exists

SignMaster V5 is widely used to design signs, stickers and vinyl lettering and to drive cutting plotters. In daily work, two things make navigating a drawing tedious:

1. **No panning with the middle mouse button.** Most design programs let you grab the canvas with the middle mouse button. In SignMaster, the middle button does nothing useful. You have to switch to the hand tool (Pan Mode) and back, or drag the scroll bars at the edge of the window.
2. **Jumpy mouse wheel zoom.** SignMaster re-centers the view on the cursor position with every wheel step. If the mouse moves only slightly between two wheel steps, the view jumps unexpectedly.

SignMasterPan was built to fix exactly these two annoyances without changing SignMaster itself. It does not modify SignMaster's files and does not inject code into it. It only reacts to your mouse input and operates SignMaster's own scroll bars and zoom shortcuts.

## Features

- **Pan with the middle mouse button:** hold and drag over the workspace. The currently selected tool stays active, and the mouse pointer does not jump.
- **Calm mouse wheel zoom:** over the workspace, the wheel sends SignMaster's zoom keys **F3** (zoom in) and **F4** (zoom out) instead of the cursor-centered zoom. Hold Ctrl/Shift/Alt/Win to use the original wheel behavior.
- **Only active in SignMaster:** in all other programs, and in SignMaster's toolbars and dialogs, the middle button and the wheel behave normally.
- **One switch for everything:** **Enabled** in the tray menu (or Ctrl+Alt+P) temporarily switches all functions off; the tray icon then turns gray.
- **Settings dialog:** all options can be changed in a window and are saved automatically.
- **German and English user interface:** follows the Windows display language; more languages can be added as text files.

---

## Contents

- [Download and installation](#download-and-installation)
- [Usage](#usage)
- [Settings](#settings)
- [Building from source](#building-from-source)
- [Files](#files)
- [How it works (technical)](#how-it-works-technical)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [License](#license)

---

## Download and installation

### Requirements

- Windows 10 or 11
- SignMaster V5 (tested with "SignMaster XPT 5.0", `Sign_Master.exe` in `C:\Program Files (x86)\FutureCorp\SignMaster\BinExe`)

Tested on a 4K monitor with 150 % Windows scaling.

### Installation

1. Download **`SignMasterPan.exe`** from the [latest release](../../releases/latest).
2. Put it into a folder of your choice where you have write access (e.g. `Documents\SignMasterPan`). On the first start, the program creates its `SignMasterPan.ini` and a `lang\` folder next to the exe.
3. Double-click **`SignMasterPan.exe`**.

A short notification appears, then the icon (white mouse with an orange wheel on a blue background) sits in the notification area. On Windows 11 it first lands in the hidden overflow area behind the **^** arrow.

To keep the icon visible:
Windows Settings → Personalization → Taskbar → *Other system tray icons* → switch **SignMasterPan** on.

Only one instance runs at a time; a second start is ignored. `SignMasterPan.exe /settings` additionally opens the settings dialog on startup (only if the program is not running yet).

### Start automatically with Windows

1. Press `Win + R`, type `shell:startup`, press Enter.
2. In the Startup folder that opens, create a shortcut to `SignMasterPan.exe` (right-click the exe → *Show more options* → *Create shortcut*, then move the shortcut there).

## Usage

| Action | Effect |
|---|---|
| **Hold and drag** the middle mouse button over the workspace | The workspace follows the mouse. The currently selected tool stays active. |
| **Esc** while dragging | Cancel the pan |
| **Wheel up** over the workspace | sends `F3` → zoom in |
| **Wheel down** over the workspace | sends `F4` → zoom out |
| Mouse wheel with **Ctrl / Shift / Alt / Win** held | passed to SignMaster unchanged |
| **Ctrl + Alt + P** | Temporarily switch all functions off and on again (same as **Enabled** in the tray menu) |

### Tray menu (right-click the icon)

| Item | Meaning |
|---|---|
| Enabled | Master switch: temporarily switches panning and mouse wheel zoom off and on again (same as Ctrl+Alt+P). Not saved; after starting, the program is always enabled. While disabled, the tray icon is gray and the middle button/mouse wheel work normally in SignMaster. |
| Settings... | Opens the [settings dialog](#settings-dialog) |
| Help | Short instructions |
| Exit | Quit the program |

## Settings

### Settings dialog

Tray menu → **Settings...** opens a window containing all settings:

| Area | Setting |
|---|---|
| General | Language (Automatic or one of the languages from `lang\`), shortcut for **Enabled** on/off |
| Pan with middle mouse button | Function switched on, speed, reverse direction |
| Mouse wheel zoom | Replace mouse wheel with keys, key for wheel up, key for wheel down |
| Diagnostics | Write log |

- **"Function switched on" (panning) and "Replace mouse wheel with keys"** permanently define which functions are used, including at program start. **Enabled** in the tray menu, in contrast, only switches everything off temporarily.
- **Every change is applied immediately and saved to `SignMasterPan.ini`.** That is why there is only *Close* and no OK button. The speed is applied as soon as you leave the field or press Enter.
- **Shortcut and zoom keys** are entered by simply pressing the desired key or key combination. Backspace clears the on/off shortcut (then there is none). If a shortcut is already used by another program, a notice appears and the old value is kept.
- **Defaults** resets all settings after a confirmation.
- While the dialog is open, the on/off shortcut is disabled so it can be typed into the input field.

### INI file

`SignMasterPan.ini` sits next to the exe and is completed with default values on startup. Changes made in the settings dialog take effect immediately; changes made directly in the file only after restarting the program.

```ini
[General]
Language=auto

[Hotkeys]
Toggle=^!p

[Pan]
Enabled=1
Speed=1
Invert=0

[Zoom]
Enabled=1
KeyIn={F3}
KeyOut={F4}

[Debug]
Log=0
```

| Section | Key | Default | Meaning |
|---|---|---|---|
| `[General]` | `Language` | `auto` | User interface language: `auto` = Windows display language (if a language file exists for it, otherwise English), `de` = German, `en` = English, or the code of another language file in `lang\`. |
| `[Hotkeys]` | `Toggle` | `^!p` | Shortcut for **Enabled** on/off (all functions, temporarily), in AutoIt notation: `^` = Ctrl, `!` = Alt, `+` = Shift, `#` = Win. If another program already uses the shortcut, a notice appears at startup. Empty = no shortcut. |
| `[Pan]` | `Enabled` | `1` | `0` = panning with the middle mouse button permanently switched off (also after program start). |
| `[Pan]` | `Speed` | `1` | Pan speed. `1` = the workspace follows the mouse 1:1, `1.2` = faster, `0.8` = slower. |
| `[Pan]` | `Invert` | `0` | `1` reverses the direction (move the view instead of the workspace). |
| `[Zoom]` | `Enabled` | `1` | `0` = do not intercept the mouse wheel; SignMaster zooms as usual. |
| `[Zoom]` | `KeyIn` | `{F3}` | Key for wheel up (AutoIt `Send` syntax, e.g. `{F3}`, `{+}`, `^{UP}`). |
| `[Zoom]` | `KeyOut` | `{F4}` | Key for wheel down. |
| `[Debug]` | `Log` | `0` | `1` writes a log to `SignMasterPan.log` (see [Troubleshooting](#troubleshooting)). |

## Building from source

SignMasterPan is written in [AutoIt](https://www.autoitscript.com/) 3.3.18. AutoIt itself is not part of this repository.

1. Download the AutoIt **portable (zip)** package from the [AutoIt downloads page](https://www.autoitscript.com/site/autoit/downloads/) and extract it into a folder named `AutoIt` inside the project folder, so that `AutoIt\AutoIt3.exe` and `AutoIt\Aut2Exe\Aut2exe.exe` exist.
2. Run the script directly:

   ```
   AutoIt\AutoIt3.exe SignMasterPan.au3
   ```

   It behaves exactly like the exe. The tray icon is then loaded from `SignMasterPan.ico`, or from `SignMasterPan_off.ico` while disabled.
3. Or build the exe: quit a running `SignMasterPan.exe` via its tray menu (otherwise the file is locked), then double-click **`build.cmd`**. It calls:

   ```
   AutoIt\Aut2Exe\Aut2exe.exe /in SignMasterPan.au3 /out SignMasterPan.exe /icon SignMasterPan.ico /x86 /nopack /comp 2
   ```

   - `/x86`: 32-bit exe; the program was tested in this variant.
   - `/nopack`: no UPX compression. Packed AutoIt programs are flagged by antivirus software more often (false positives).
   - The language files and the gray tray icon are embedded into the exe.

Syntax check without compiling:

```
AutoIt\Au3Check.exe SignMasterPan.au3
```

The icons are generated by `tools\make_icon.ps1`:

```
powershell -ExecutionPolicy Bypass -File tools\make_icon.ps1 -OutIco SignMasterPan.ico
powershell -ExecutionPolicy Bypass -File tools\make_icon.ps1 -OutIco SignMasterPan_off.ico -Gray
```

## Files

| File | Description |
|---|---|
| `SignMasterPan.au3` | Source code (AutoIt) |
| `SignMasterPan.ico` | Program and tray icon (16–256 px) |
| `SignMasterPan_off.ico` | Gray tray icon for the disabled state (embedded in the exe) |
| `lang\de.lng`, `lang\en.lng` | Language files containing all user interface texts |
| `build.cmd` | Builds the exe (requires AutoIt in `AutoIt\`) |
| `tools\make_icon.ps1` | Generates both icons (`-Gray` for the gray variant) |
| `LICENSE` | MIT license |
| `SignMasterPan.exe` | Compiled program; not in the repository, see [Releases](../../releases) |
| `SignMasterPan.ini`, `SignMasterPan.log` | Created at runtime next to the exe; not in the repository |

## How it works (technical)

### Mouse hook

A system-wide low-level mouse hook (`WH_MOUSE_LL`) watches the middle button and the mouse wheel. An event is only intercepted if

- the active window is the SignMaster main window (window class `TVmAppMainform.UnicodeClass`), and
- the window under the mouse pointer belongs to a document window (`TVmDocWindow.UnicodeClass`).

Input generated by the program itself (injected input) is ignored. The hook only sets flags; the main loop does the actual work so that the hook returns quickly.

### Panning via the scroll sliders

SignMaster does not react to `WM_HSCROLL`/`WM_VSCROLL`, and the mouse wheel always zooms. However, the scroll sliders at the bottom and right of the document window are `TRangeBar` controls from the Delphi graphics library **Graphics32**. They evaluate mouse messages using the coordinates contained in the message, so they can be operated via `PostMessage` without moving the real mouse pointer:

1. **When the middle button is pressed**, both sliders of the document window are rendered into a memory bitmap with `PrintWindow`. The thumb is located on the center line as the longest run whose color differs from the track color. Important: pixels are read with `GetPixel`, because `GetDIBits` only returns background for SignMaster.
2. **Conversion factor** per direction = thumb length ÷ length of the visible workspace. The workspace size is derived from the position of the slider panels and the ruler.
3. **On every mouse movement** the movement is multiplied by the factor. As soon as a whole thumb pixel has accumulated, the slider receives the sequence `WM_LBUTTONDOWN` (on the thumb) → `WM_MOUSEMOVE` (shifted) → `WM_LBUTTONUP`. SignMaster then scrolls the view itself. The thumb position is tracked internally and clamped to the ends of the track so that the click never lands next to the thumb.

Advantages: the tool is not switched, and the mouse pointer does not jump.

### Mouse wheel zoom

The wheel delta is accumulated. For every full notch (120), `KeyIn` or `KeyOut` is sent to SignMaster via `Send`. Finer deltas (touchpads, free-spinning wheels) are collected until a full notch is reached.

### Enabled / disabled

The master switch only sets a flag that the mouse hook checks. Switching off ends a running pan and discards zoom steps that have not been sent yet. The gray icon is embedded in the exe and extracted to `%TEMP%\SignMasterPan_off.ico` on startup.

### Languages

All user interface texts live in language files in the `lang\` folder, one file per language (`de.lng`, `en.lng`). The format is a simple INI-like text format in UTF-8:

```ini
[Language]
Code=en
Name=English

[Strings]
tray_help=Help
start=Running. Drag with the middle mouse button to pan the workspace.
hk_busy=The hotkey %1 is already in use.\nEnter a different key.
```

- `\n` inserts a line break; `%1` to `%4` are placeholders filled in by the program.
- In the script, `_T("key")` returns the text in the current language. If a text is missing, the English one is used; if that is missing too, the key itself.
- **Adding a language:** copy `en.lng`, e.g. to `fr.lng`, adjust `Code`/`Name` and translate the texts. After a restart the language appears in the settings dialog automatically and is chosen with `Language=auto` when Windows runs in that language. Contributions of new languages are welcome.
- The exe embeds `de.lng` and `en.lng` and extracts them to `lang\` on startup if they are missing there. Existing files are not overwritten, so your own changes are kept. After an update with new texts, delete the old files so the new ones get extracted.

### Note on display scaling

SignMaster runs as "DPI-unaware" (compatibility setting). AutoIt also works in the scaled 96-DPI coordinate system, so a mouse movement of X pixels corresponds to exactly X pixels in SignMaster. Screenshots taken by DPI-unaware programs, on the other hand, only capture the physical top-left part of the screen. Keep this in mind when debugging with screenshots.

## Troubleshooting

### Enabling the log

Enable *Write log* in the settings (or set `[Debug] Log=1` in `SignMasterPan.ini` and restart the program). `SignMasterPan.log` then contains, among other things:

- `MBUTTONDOWN active=… pan=… over=True/False window=… under=…`: whether the middle click was detected, whether the program is enabled and panning switched on, and which window it was over
- `Active=True/False`: toggling **Enabled**
- `PanBegin … H=… V=… kH=… kV=…`: sliders found, thumb position/length and conversion factors
- `BarInfo …: no thumb found`: slider without a recognizable thumb
- `move H/V …`: every thumb movement sent

Switch the log off again afterwards, otherwise the file grows with every movement.

### Self-test

```
SignMasterPan.exe /selftest
```

Simulates a pan (200 px to the left, 120 px up) in SignMaster's first document window without using the mouse, then exits. With the log enabled, the details are written to the log. The self-test also runs while the program is already active in the background.

### Common problems

| Problem | Cause / solution |
|---|---|
| Nothing happens when dragging | If the whole drawing is visible, SignMaster shows no thumb, so there is nothing to scroll. Otherwise enable the log and check that `over=True` appears and sliders are found. |
| Notice "hotkey already in use" | Choose a different on/off shortcut in the settings dialog. |
| Workspace moves faster/slower than the mouse | Adjust the speed in the settings dialog. |
| Mouse wheel should zoom the original way again | Settings → uncheck "Replace mouse wheel with keys", or temporarily switch everything off via **Enabled** in the tray menu. |
| Does not work while SignMaster runs as administrator | Windows blocks input from normal to elevated programs. Start SignMasterPan as administrator as well. |
| Antivirus flags the exe | A false positive typical for AutoIt programs. Add the file as an exception or run the script directly with `AutoIt3.exe`. |

## Limitations

- At very high zoom levels the thumb becomes small; one thumb pixel then corresponds to many workspace pixels, and panning becomes steppy.
- Panning stops at the edge of the scroll area, just like dragging the slider.
- Pan direction and speed are determined once when the middle button is pressed. If the zoom changes meanwhile (e.g. via the mouse wheel), the factor is no longer exact until the next press.
- Depends on SignMaster internals (window classes, Graphics32 sliders). A SignMaster update may require adjustments.

## License

SignMasterPan is released under the [MIT License](LICENSE).

This project is not affiliated with, endorsed by or supported by FutureCorp. SignMaster is a product of its respective owner; all trademarks belong to their owners.
