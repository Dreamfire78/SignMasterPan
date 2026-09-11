; =============================================================================
; SignMasterPan.au3
; Pan the SignMaster workspace by dragging with the middle mouse button,
; without switching tools. User interface texts come from language files.
;
; How it works:
;   The scroll sliders at the bottom and right of the document window are
;   Graphics32 TRangeBar controls. They evaluate mouse messages using the
;   coordinates contained in the message. While the middle button is held,
;   every mouse movement is converted into a short "grab thumb / move /
;   release" sequence and posted to the sliders via PostMessage.
;   The real mouse pointer and the active tool stay untouched.
;
; Mouse wheel zoom:
;   SignMaster re-centers the view on the cursor when zooming with the wheel.
;   Instead, the wheel is intercepted over the workspace and F3 (zoom in) or
;   F4 (zoom out) is sent. With Ctrl/Shift/Alt/Win held, the wheel is passed
;   through unchanged.
;
; Enabled / disabled:
;   The tray item "Enabled" (or the shortcut, default Ctrl+Alt+P) temporarily
;   switches all functions off and on. This state is not saved; after a start
;   the program is always enabled. While disabled, the tray icon is gray.
;   Which functions are used is set in the settings ([Pan] Enabled, [Zoom] Enabled).
;
; Settings: tray menu -> Settings... (saved immediately) or SignMasterPan.ini
;   [General] Language = auto   auto (Windows display language) or a language code (de, en, ...)
;   [Hotkeys] Toggle   = ^!p    shortcut for enabled on/off (empty = none)
;   [Pan] Enabled = 1           pan function switched on
;   [Pan] Speed   = 1.0         pan speed factor (1.0 = workspace follows the mouse)
;   [Pan] Invert  = 0           1 = reverse direction
;   [Zoom] Enabled = 1          replace the mouse wheel with keys
;   [Zoom] KeyIn   = {F3}       key for wheel up
;   [Zoom] KeyOut  = {F4}       key for wheel down
;   [Debug] Log    = 0          1 = write SignMasterPan.log
;
; Language files: lang\<code>.lng (UTF-8, sections [Language] and [Strings]).
;   The compiled exe embeds de.lng, en.lng and the gray tray icon.
; =============================================================================

#include <WinAPISys.au3>
#include <WinAPISysWin.au3>
#include <WinAPIMisc.au3>
#include <WinAPIConv.au3>
#include <WinAPIGdi.au3>
#include <WinAPIGdiDC.au3>
#include <WinAPIConstants.au3>
#include <WindowsConstants.au3>
#include <APISysConstants.au3>
#include <GUIConstantsEx.au3>
#include <ComboConstants.au3>
#include <FileConstants.au3>
#include <TrayConstants.au3>
#include <SendMessage.au3>
#include <Misc.au3>

Opt("MouseCoordMode", 1)
Opt("TrayMenuMode", 3)
Opt("TrayOnEventMode", 1)
Opt("GUIOnEventMode", 1)

; "/selftest": simulates a pan in the first document window (no mouse button needed) and writes to the log
Global $g_bSelfTest = ($CmdLine[0] > 0 And $CmdLine[1] = "/selftest")
If Not $g_bSelfTest Then _Singleton("SignMasterPan_Singleton")

Global Const $APP_TITLE = "SignMaster Pan"
Global Const $SM_MAIN_CLASS = "TVmAppMainform.UnicodeClass"
Global Const $SM_DOC_CLASS = "TVmDocWindow.UnicodeClass"
Global Const $SM_BAR_CLASS = "TRangeBar"
Global Const $INI = @ScriptDir & "\SignMasterPan.ini"
Global Const $LANG_DIR = @ScriptDir & "\lang"
Global Const $LANG_FALLBACK = "en"
Global Const $ICON_ON = @ScriptDir & "\SignMasterPan.ico"
Global Const $ICON_OFF = @Compiled ? @TempDir & "\SignMasterPan_off.ico" : @ScriptDir & "\SignMasterPan_off.ico"
Global Const $LLMHF_INJECTED = 0x01
Global Const $MK_LBUTTON = 0x0001
Global Const $tagMSLLHOOK = "struct;long X;long Y;endstruct;dword mouseData;dword flags;dword time;ulong_ptr dwExtraInfo"

; Hotkey control (msctls_hotkey32)
Global Const $HKM_SETHOTKEY = 0x0401, $HKM_GETHOTKEY = 0x0402, $HKM_SETRULES = 0x0403
Global Const $HOTKEYF_SHIFT = 0x01, $HOTKEYF_CONTROL = 0x02, $HOTKEYF_ALT = 0x04, $HOTKEYF_EXT = 0x08
Global Const $EN_CHANGE_CODE = 0x0300, $EN_KILLFOCUS_CODE = 0x0200

; Default settings
Global Const $DEF_LANGUAGE = "auto", $DEF_TOGGLE = "^!p", $DEF_SPEED = 1.0
Global Const $DEF_ZOOM_IN = "{F3}", $DEF_ZOOM_OUT = "{F4}"

; Indexes into slider info arrays
Global Const $BAR_HWND = 0, $BAR_LEN = 1, $BAR_THICK = 2, $BAR_THUMB = 3, $BAR_THUMBLEN = 4, $BAR_HORZ = 5
; Indexes into the language list
Global Const $LANG_CODE = 0, $LANG_NAME = 1, $LANG_PATH = 2

; --- Embedded files and language -------------------------------------------------
Global $g_oStr = ObjCreate("Scripting.Dictionary")          ; texts of the active language
Global $g_oStrFallback = ObjCreate("Scripting.Dictionary")  ; English texts for missing keys
_InstallEmbeddedFiles()
Global $g_aLangs = _LangScan()
Global $g_sLangSetting = StringLower(IniRead($INI, "General", "Language", $DEF_LANGUAGE))
If $g_sLangSetting <> "auto" And _LangIndex($g_sLangSetting) < 0 Then $g_sLangSetting = "auto"
Global $g_sLang = ""
_LangLoad(_ResolveLang($g_sLangSetting))

; --- Settings (saved) ------------------------------------------------------------
Global $g_bPanEnabled = (Int(IniRead($INI, "Pan", "Enabled", 1)) = 1)
Global $g_fSpeed = Number(IniRead($INI, "Pan", "Speed", $DEF_SPEED))
If $g_fSpeed < 0.1 Or $g_fSpeed > 5 Then $g_fSpeed = $DEF_SPEED
Global $g_iDir = (Int(IniRead($INI, "Pan", "Invert", 0)) = 1) ? -1 : 1
Global $g_sHkToggle = IniRead($INI, "Hotkeys", "Toggle", $DEF_TOGGLE)
Global $g_bZoomEnabled = (Int(IniRead($INI, "Zoom", "Enabled", 1)) = 1)
Global $g_sZoomIn = IniRead($INI, "Zoom", "KeyIn", $DEF_ZOOM_IN)
Global $g_sZoomOut = IniRead($INI, "Zoom", "KeyOut", $DEF_ZOOM_OUT)
Global $g_bLog = (Int(IniRead($INI, "Debug", "Log", 0)) = 1)
_SaveSettings()

; --- State -------------------------------------------------------------------------
Global $g_bActive = True     ; master switch (tray "Enabled"), temporary, not saved
Global $g_bStartRequested = False
Global $g_bEndRequested = False
Global $g_bPanning = False
Global $g_bSwallowUp = False
Global $g_hDoc = 0
Global $g_aBarH = 0, $g_aBarV = 0
Global $g_fKH = 0, $g_fKV = 0
Global $g_fAccX = 0, $g_fAccY = 0
Global $g_iLastX = 0, $g_iLastY = 0
Global $g_iWheelAcc = 0     ; wheel delta that has not yet reached a full notch (120)
Global $g_iZoomQueue = 0    ; > 0: send zoom in this many times, < 0: zoom out

; --- Settings dialog state --------------------------------------------------------
Global $g_hSetGUI = 0
Global $g_idSetLang, $g_idSetPanEnabled, $g_idSetSpeed, $g_idSetInvert, $g_idSetZoomEnabled, $g_idSetLog
Global $g_hSetHkToggle = 0, $g_hSetHkIn = 0, $g_hSetHkOut = 0
Global $g_bSetHkDirty = False   ; a hotkey control changed; applied by the main loop
Global $g_bSetReopen = False    ; rebuild the dialog (e.g. after a language change)

; --- Log ---------------------------------------------------------------------------
Global Const $LOG = @ScriptDir & "\SignMasterPan.log"
Global $g_sDbgDown = ""

If $g_bSelfTest Then
	_SelfTest()
	Exit
EndIf
_Log("Start lang=" & $g_sLang & " (" & UBound($g_aLangs) & " language files)")

; --- Tray menu -----------------------------------------------------------------------
; Note: TrayCreateItem("") creates a separator, so real items must get their text on creation
Global $g_idTrayActive = TrayCreateItem(_T("tray_active"))
TrayItemSetState($g_idTrayActive, $TRAY_CHECKED)
TrayItemSetOnEvent($g_idTrayActive, "_ToggleActive")
TrayCreateItem("")
Global $g_idTraySettings = TrayCreateItem(_T("tray_settings"))
TrayItemSetOnEvent($g_idTraySettings, "_SettingsOpen")
Global $g_idTrayHelp = TrayCreateItem(_T("tray_help"))
TrayItemSetOnEvent($g_idTrayHelp, "_ShowHelp")
TrayCreateItem("")
Global $g_idTrayExit = TrayCreateItem(_T("tray_exit"))
TrayItemSetOnEvent($g_idTrayExit, "_Exit")
_UpdateTrayTexts()
TraySetState($TRAY_ICONSTATE_SHOW)

_RegisterToggleHotkey()
GUIRegisterMsg($WM_COMMAND, "_WM_COMMAND")

; --- Mouse hook ----------------------------------------------------------------------
Global $g_hHookProc = DllCallbackRegister("_MouseProc", "lresult", "int;wparam;lparam")
Global $g_hHook = _WinAPI_SetWindowsHookEx($WH_MOUSE_LL, DllCallbackGetPtr($g_hHookProc), _WinAPI_GetModuleHandle(0))
If Not $g_hHook Then
	MsgBox(16, $APP_TITLE, _T("hook_fail"))
	Exit 1
EndIf
OnAutoItExitRegister("_Cleanup")

TrayTip($APP_TITLE, _T("start"), 3, $TIP_ICONASTERISK)
; "/settings": open the settings dialog right after startup
If $CmdLine[0] > 0 And $CmdLine[1] = "/settings" Then _SettingsOpen()

; --- Main loop -------------------------------------------------------------------------
While 1
	Sleep(10)
	If $g_sDbgDown <> "" Then
		_Log($g_sDbgDown)
		$g_sDbgDown = ""
	EndIf
	While $g_iZoomQueue <> 0
		If $g_iZoomQueue > 0 Then
			$g_iZoomQueue -= 1
			Send($g_sZoomIn)
		Else
			$g_iZoomQueue += 1
			Send($g_sZoomOut)
		EndIf
	WEnd
	If $g_bStartRequested Then
		$g_bStartRequested = False
		_PanBegin()
	EndIf
	If $g_bPanning Then
		If $g_bEndRequested Or _IsPressed("1B") Or Not $g_bActive Then
			$g_bPanning = False
		Else
			_PanStep()
		EndIf
	EndIf
	If Not $g_bPanning Then $g_bEndRequested = False
	If $g_bSetHkDirty Then _SettingsApplyHotkeys()
	If $g_bSetReopen Then
		$g_bSetReopen = False
		If $g_hSetGUI Then
			_SettingsClose()
			_SettingsOpen()
		EndIf
	EndIf
WEnd

; =============================================================================
; Hook: only sets flags; the main loop does the actual work.
; =============================================================================
Func _MouseProc($nCode, $wParam, $lParam)
	If $nCode >= 0 Then
		Local $tInfo = DllStructCreate($tagMSLLHOOK, $lParam)
		If Not BitAND(DllStructGetData($tInfo, "flags"), $LLMHF_INJECTED) Then
			Switch $wParam
				Case $WM_MBUTTONDOWN
					Local $bOver = $g_bActive And $g_bPanEnabled And Not $g_bPanning And Not $g_bSwallowUp And _IsOverSignMasterDoc()
					If $g_bLog Then
						Local $tPt = _WinAPI_GetMousePos()
						$g_sDbgDown = "MBUTTONDOWN active=" & $g_bActive & " pan=" & $g_bPanEnabled & " panning=" & $g_bPanning & " over=" & $bOver & _
								" window=" & _WinAPI_GetClassName(WinGetHandle("[ACTIVE]")) & _
								" under=" & _WinAPI_GetClassName(_WinAPI_WindowFromPoint($tPt))
					EndIf
					If $bOver Then
						$g_bSwallowUp = True
						$g_bStartRequested = True
						Return 1
					EndIf
				Case $WM_MBUTTONUP
					If $g_bSwallowUp Then
						$g_bSwallowUp = False
						$g_bEndRequested = True
						Return 1
					EndIf
				Case $WM_MOUSEWHEEL
					If $g_bActive And $g_bZoomEnabled And Not _ModifierDown() And _IsOverSignMasterDoc() Then
						; The wheel delta is the signed high word of mouseData
						Local $iWheel = BitAND(BitShift(DllStructGetData($tInfo, "mouseData"), 16), 0xFFFF)
						If $iWheel >= 0x8000 Then $iWheel -= 0x10000
						$g_iWheelAcc += $iWheel
						While $g_iWheelAcc >= 120
							$g_iWheelAcc -= 120
							$g_iZoomQueue += 1
						WEnd
						While $g_iWheelAcc <= -120
							$g_iWheelAcc += 120
							$g_iZoomQueue -= 1
						WEnd
						Return 1
					EndIf
			EndSwitch
		EndIf
	EndIf
	Return _WinAPI_CallNextHookEx($g_hHook, $nCode, $wParam, $lParam)
EndFunc

; Is SignMaster the active window and is the mouse over a document window?
Func _IsOverSignMasterDoc()
	Local $hActive = WinGetHandle("[ACTIVE]")
	If _WinAPI_GetClassName($hActive) <> $SM_MAIN_CLASS Then Return False

	Local $tPoint = _WinAPI_GetMousePos()
	Local $hWnd = _WinAPI_WindowFromPoint($tPoint)
	If Not $hWnd Then Return False
	If _WinAPI_GetAncestor($hWnd, $GA_ROOT) <> $hActive Then Return False

	While $hWnd And $hWnd <> $hActive
		If _WinAPI_GetClassName($hWnd) = $SM_DOC_CLASS Then
			$g_hDoc = $hWnd
			Return True
		EndIf
		$hWnd = _WinAPI_GetParent($hWnd)
	WEnd
	Return False
EndFunc

; =============================================================================
; Pan
; =============================================================================
Func _PanBegin()
	$g_aBarH = 0
	$g_aBarV = 0
	Local $aChildren = _WinAPI_EnumChildWindows($g_hDoc, False)
	If @error Then Return
	For $i = 1 To $aChildren[0][0]
		If $aChildren[$i][1] <> $SM_BAR_CLASS Or Not _WinAPI_IsWindowVisible($aChildren[$i][0]) Then ContinueLoop
		Local $aBar = _BarInfo($aChildren[$i][0])
		If Not IsArray($aBar) Then ContinueLoop
		If $aBar[$BAR_HORZ] Then
			$g_aBarH = $aBar
		Else
			$g_aBarV = $aBar
		EndIf
	Next

	; Ratio of thumb movement to workspace movement: thumb length / visible workspace length
	Local $aCanvas = _CanvasSize()
	$g_fKH = IsArray($g_aBarH) ? $g_aBarH[$BAR_THUMBLEN] / $aCanvas[0] * $g_fSpeed : 0
	$g_fKV = IsArray($g_aBarV) ? $g_aBarV[$BAR_THUMBLEN] / $aCanvas[1] * $g_fSpeed : 0

	Local $aPos = MouseGetPos()
	$g_iLastX = $aPos[0]
	$g_iLastY = $aPos[1]
	$g_fAccX = 0
	$g_fAccY = 0
	$g_bPanning = True
	_Log("PanBegin doc=" & $g_hDoc & " canvas=" & $aCanvas[0] & "x" & $aCanvas[1] & _
			" H=" & _BarText($g_aBarH) & " kH=" & Round($g_fKH, 4) & _
			" V=" & _BarText($g_aBarV) & " kV=" & Round($g_fKV, 4))
EndFunc

Func _PanStep()
	Local $aPos = MouseGetPos()
	Local $iDX = $aPos[0] - $g_iLastX, $iDY = $aPos[1] - $g_iLastY
	$g_iLastX = $aPos[0]
	$g_iLastY = $aPos[1]
	_PanApply($iDX, $iDY)
EndFunc

Func _PanApply($iDX, $iDY)
	If $iDX <> 0 And IsArray($g_aBarH) Then
		$g_fAccX -= $iDX * $g_fKH * $g_iDir
		Local $iStepX = Int($g_fAccX)
		If $iStepX <> 0 Then
			$g_fAccX -= $iStepX
			_MoveThumb($g_aBarH, $iStepX)
		EndIf
	EndIf
	If $iDY <> 0 And IsArray($g_aBarV) Then
		$g_fAccY -= $iDY * $g_fKV * $g_iDir
		Local $iStepY = Int($g_fAccY)
		If $iStepY <> 0 Then
			$g_fAccY -= $iStepY
			_MoveThumb($g_aBarV, $iStepY)
		EndIf
	EndIf
EndFunc

; Drag the thumb by $iDelta pixels via messages (grab, move, release).
Func _MoveThumb(ByRef $aBar, $iDelta)
	Local $iMin = $aBar[$BAR_THICK]
	Local $iMax = $aBar[$BAR_LEN] - $aBar[$BAR_THICK] - $aBar[$BAR_THUMBLEN]
	Local $iNew = $aBar[$BAR_THUMB] + $iDelta
	If $iNew < $iMin Then $iNew = $iMin
	If $iNew > $iMax Then $iNew = $iMax
	$iDelta = $iNew - $aBar[$BAR_THUMB]
	If $iDelta = 0 Then Return

	Local $iAlong = $aBar[$BAR_THUMB] + Int($aBar[$BAR_THUMBLEN] / 2)
	Local $iAcross = Int($aBar[$BAR_THICK] / 2)
	Local $hBar = $aBar[$BAR_HWND]
	If $aBar[$BAR_HORZ] Then
		_WinAPI_PostMessage($hBar, $WM_LBUTTONDOWN, $MK_LBUTTON, _WinAPI_MakeLong($iAlong, $iAcross))
		_WinAPI_PostMessage($hBar, $WM_MOUSEMOVE, $MK_LBUTTON, _WinAPI_MakeLong($iAlong + $iDelta, $iAcross))
		_WinAPI_PostMessage($hBar, $WM_LBUTTONUP, 0, _WinAPI_MakeLong($iAlong + $iDelta, $iAcross))
	Else
		_WinAPI_PostMessage($hBar, $WM_LBUTTONDOWN, $MK_LBUTTON, _WinAPI_MakeLong($iAcross, $iAlong))
		_WinAPI_PostMessage($hBar, $WM_MOUSEMOVE, $MK_LBUTTON, _WinAPI_MakeLong($iAcross, $iAlong + $iDelta))
		_WinAPI_PostMessage($hBar, $WM_LBUTTONUP, 0, _WinAPI_MakeLong($iAcross, $iAlong + $iDelta))
	EndIf
	$aBar[$BAR_THUMB] = $iNew
	_Log("  move " & ($aBar[$BAR_HORZ] ? "H" : "V") & " " & $iDelta & " -> thumb " & $iNew)
EndFunc

; Render the slider via PrintWindow and locate the thumb:
; the longest run on the center line whose color differs from the track color.
; Returns an info array (see $BAR_*) or 0 if the slider cannot scroll.
Func _BarInfo($hBar)
	Local $tRect = _WinAPI_GetClientRect($hBar)
	Local $iW = DllStructGetData($tRect, 3), $iH = DllStructGetData($tRect, 4)
	If $iW < 2 Or $iH < 2 Then Return 0
	Local $bHorz = ($iW > $iH)
	Local $iLen = $bHorz ? $iW : $iH
	Local $iThick = $bHorz ? $iH : $iW

	Local $hWndDC = _WinAPI_GetDC($hBar)
	Local $hMemDC = _WinAPI_CreateCompatibleDC($hWndDC)
	Local $hBmp = _WinAPI_CreateCompatibleBitmap($hWndDC, $iW, $iH)
	Local $hOld = _WinAPI_SelectObject($hMemDC, $hBmp)
	_WinAPI_PrintWindow($hBar, $hMemDC, True)

	; Read the center line with GetPixel (GetDIBits returns only background for SignMaster)
	Local $aCol[$iLen]
	Local $iMid = Int($iThick / 2)
	For $i = 0 To $iLen - 1
		$aCol[$i] = $bHorz ? _WinAPI_GetPixel($hMemDC, $i, $iMid) : _WinAPI_GetPixel($hMemDC, $iMid, $i)
	Next

	_WinAPI_SelectObject($hMemDC, $hOld)
	_WinAPI_DeleteObject($hBmp)
	_WinAPI_DeleteDC($hMemDC)
	_WinAPI_ReleaseDC($hBar, $hWndDC)

	; Track color = most frequent color between the arrow buttons
	Local $oCount = ObjCreate("Scripting.Dictionary")
	For $i = $iThick To $iLen - $iThick - 1
		$oCount.Item($aCol[$i]) = $oCount.Item($aCol[$i]) + 1
	Next
	Local $iTrack = 0, $iMaxCount = 0
	For $vKey In $oCount.Keys
		If $oCount.Item($vKey) > $iMaxCount Then
			$iMaxCount = $oCount.Item($vKey)
			$iTrack = $vKey
		EndIf
	Next

	Local $iBestStart = -1, $iBestLen = 0, $iRunStart = -1
	For $i = $iThick To $iLen - $iThick
		Local $bThumb = ($i < $iLen - $iThick) And ($aCol[$i] <> $iTrack)
		If $bThumb And $iRunStart < 0 Then $iRunStart = $i
		If Not $bThumb And $iRunStart >= 0 Then
			If $i - $iRunStart > $iBestLen Then
				$iBestLen = $i - $iRunStart
				$iBestStart = $iRunStart
			EndIf
			$iRunStart = -1
		EndIf
	Next
	If $iBestStart < 0 Or $iBestLen < 3 Or $iBestLen >= $iLen - 2 * $iThick - 1 Then
		_Log("  BarInfo " & $hBar & " " & $iW & "x" & $iH & ": no thumb found (track=" & Hex($iTrack, 6) & _
				" color[mid]=" & Hex($aCol[Int($iLen / 2)], 6) & " run=" & $iBestStart & "/" & $iBestLen & ")")
		Return 0
	EndIf

	Local $aBar[6] = [$hBar, $iLen, $iThick, $iBestStart, $iBestLen, $bHorz]
	Return $aBar
EndFunc

; Visible workspace of the document window [width, height]:
; between the ruler and the slider panels at the right/bottom.
Func _CanvasSize()
	Local $tRect = _WinAPI_GetClientRect($g_hDoc)
	Local $aSize[2] = [DllStructGetData($tRect, 3) - 50, DllStructGetData($tRect, 4) - 80]
	Local $tOrigin = DllStructCreate($tagPOINT)
	_WinAPI_ClientToScreen($g_hDoc, $tOrigin)

	If IsArray($g_aBarV) Then
		Local $aVBar = WinGetPos($g_aBarV[$BAR_HWND])
		Local $aVPanel = WinGetPos(_WinAPI_GetParent($g_aBarV[$BAR_HWND]))
		Local $iRuler = $aVBar[1] - $aVPanel[1]
		$aSize[0] = $aVPanel[0] - DllStructGetData($tOrigin, "X") - $iRuler
		If IsArray($g_aBarH) Then
			Local $aHPanel = WinGetPos(_WinAPI_GetParent($g_aBarH[$BAR_HWND]))
			$aSize[1] = $aHPanel[1] - $aVBar[1]
		EndIf
	EndIf
	If $aSize[0] < 50 Then $aSize[0] = 50
	If $aSize[1] < 50 Then $aSize[1] = 50
	Return $aSize
EndFunc

; =============================================================================
; Enabled / disabled (tray master switch)
; =============================================================================
Func _ToggleActive()
	$g_bActive = Not $g_bActive
	If Not $g_bActive Then
		; stop anything that is in progress
		$g_bPanning = False
		$g_bStartRequested = False
		$g_iZoomQueue = 0
		$g_iWheelAcc = 0
	EndIf
	TrayItemSetState($g_idTrayActive, $g_bActive ? $TRAY_CHECKED : $TRAY_UNCHECKED)
	_UpdateTrayIcon()
	TrayTip($APP_TITLE, _T($g_bActive ? "active_on" : "active_off"), 2, $TIP_ICONASTERISK)
	_Log("Active=" & $g_bActive)
EndFunc

; Colored icon while enabled, gray icon while disabled.
Func _UpdateTrayIcon()
	If $g_bActive Then
		If @Compiled Then
			TraySetIcon()                  ; embedded exe icon
		ElseIf FileExists($ICON_ON) Then
			TraySetIcon($ICON_ON)
		EndIf
	ElseIf FileExists($ICON_OFF) Then
		TraySetIcon($ICON_OFF)
	EndIf
	TraySetToolTip(_T($g_bActive ? "tooltip" : "tooltip_off"))
EndFunc

Func _UpdateTrayTexts()
	TrayItemSetText($g_idTrayActive, _T("tray_active"))
	TrayItemSetText($g_idTraySettings, _T("tray_settings"))
	TrayItemSetText($g_idTrayHelp, _T("tray_help"))
	TrayItemSetText($g_idTrayExit, _T("tray_exit"))
	_UpdateTrayIcon()
EndFunc

; =============================================================================
; Settings
; =============================================================================

; Write all settings to the INI file.
Func _SaveSettings()
	IniWrite($INI, "General", "Language", $g_sLangSetting)
	IniWrite($INI, "Hotkeys", "Toggle", $g_sHkToggle)
	IniWrite($INI, "Pan", "Enabled", $g_bPanEnabled ? 1 : 0)
	IniWrite($INI, "Pan", "Speed", $g_fSpeed)
	IniWrite($INI, "Pan", "Invert", ($g_iDir = -1) ? 1 : 0)
	IniWrite($INI, "Zoom", "Enabled", $g_bZoomEnabled ? 1 : 0)
	IniWrite($INI, "Zoom", "KeyIn", $g_sZoomIn)
	IniWrite($INI, "Zoom", "KeyOut", $g_sZoomOut)
	IniWrite($INI, "Debug", "Log", $g_bLog ? 1 : 0)
EndFunc

; Register the enabled on/off shortcut (not while the settings dialog is open, so it can be typed there).
Func _RegisterToggleHotkey()
	If $g_sHkToggle = "" Or $g_hSetGUI Then Return
	If Not HotKeySet($g_sHkToggle, "_ToggleActive") Then MsgBox(48, $APP_TITLE, _T("hk_busy", _HotkeyName($g_sHkToggle)), 15)
EndFunc

Func _UnregisterToggleHotkey()
	If $g_sHkToggle <> "" Then HotKeySet($g_sHkToggle)
EndFunc

Func _SettingsOpen()
	If $g_hSetGUI Then
		WinActivate($g_hSetGUI)
		Return
	EndIf
	_UnregisterToggleHotkey()

	Local $iW = 520, $iH = 460, $iLblW = 170, $iCtlX = 200
	Local $iCtlW = $iW - $iCtlX - 25   ; width of the input column
	$g_hSetGUI = GUICreate(_T("set_title"), $iW, $iH, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), $WS_EX_TOPMOST)
	GUISetFont(9, 400, 0, "Segoe UI", $g_hSetGUI)
	GUISetOnEvent($GUI_EVENT_CLOSE, "_SettingsClose", $g_hSetGUI)

	; General: language and enabled on/off shortcut
	GUICtrlCreateGroup(_T("set_general"), 10, 10, $iW - 20, 88)
	Local $idFontRef = GUICtrlCreateLabel(_T("set_language"), 25, 35, $iLblW, 20)
	$g_idSetLang = GUICtrlCreateCombo("", $iCtlX, 31, $iCtlW, 22, BitOR($CBS_DROPDOWNLIST, $WS_VSCROLL))
	Local $sItems = _T("lang_auto"), $sSel = _T("lang_auto")
	For $i = 0 To UBound($g_aLangs) - 1
		$sItems &= "|" & $g_aLangs[$i][$LANG_NAME]
		If $g_aLangs[$i][$LANG_CODE] = $g_sLangSetting Then $sSel = $g_aLangs[$i][$LANG_NAME]
	Next
	GUICtrlSetData($g_idSetLang, $sItems, $sSel)
	GUICtrlSetOnEvent($g_idSetLang, "_SetOnLanguage")
	GUICtrlCreateLabel(_T("set_hotkey"), 25, 67, $iLblW, 20)
	GUICtrlCreateGroup("", -99, -99, 1, 1)

	; Pan
	GUICtrlCreateGroup(_T("set_pan"), 10, 108, $iW - 20, 110)
	$g_idSetPanEnabled = GUICtrlCreateCheckbox(_T("set_pan_enabled"), 25, 130, $iW - 50, 20)
	GUICtrlSetState($g_idSetPanEnabled, $g_bPanEnabled ? $GUI_CHECKED : $GUI_UNCHECKED)
	GUICtrlSetOnEvent($g_idSetPanEnabled, "_SetOnPanEnabled")
	GUICtrlCreateLabel(_T("set_speed"), 25, 160, $iLblW, 20)
	$g_idSetSpeed = GUICtrlCreateInput(String($g_fSpeed), $iCtlX, 157, 50, 22)
	GUICtrlSetOnEvent($g_idSetSpeed, "_SetOnSpeed")
	GUICtrlCreateLabel(_T("set_speed_hint"), $iCtlX + 58, 160, $iCtlW - 58, 20)
	$g_idSetInvert = GUICtrlCreateCheckbox(_T("set_invert"), 25, 188, $iW - 50, 20)
	GUICtrlSetState($g_idSetInvert, ($g_iDir = -1) ? $GUI_CHECKED : $GUI_UNCHECKED)
	GUICtrlSetOnEvent($g_idSetInvert, "_SetOnInvert")
	GUICtrlCreateGroup("", -99, -99, 1, 1)

	; Mouse wheel zoom
	GUICtrlCreateGroup(_T("set_zoom"), 10, 228, $iW - 20, 110)
	$g_idSetZoomEnabled = GUICtrlCreateCheckbox(_T("set_zoom_enabled"), 25, 250, $iW - 50, 20)
	GUICtrlSetState($g_idSetZoomEnabled, $g_bZoomEnabled ? $GUI_CHECKED : $GUI_UNCHECKED)
	GUICtrlSetOnEvent($g_idSetZoomEnabled, "_SetOnZoomEnabled")
	GUICtrlCreateLabel(_T("set_zoom_in"), 25, 279, $iLblW, 20)
	GUICtrlCreateLabel(_T("set_zoom_out"), 25, 308, $iLblW, 20)
	GUICtrlCreateGroup("", -99, -99, 1, 1)

	; Diagnostics
	GUICtrlCreateGroup(_T("set_debug"), 10, 348, $iW - 20, 50)
	$g_idSetLog = GUICtrlCreateCheckbox(_T("set_log"), 25, 370, $iW - 50, 20)
	GUICtrlSetState($g_idSetLog, $g_bLog ? $GUI_CHECKED : $GUI_UNCHECKED)
	GUICtrlSetOnEvent($g_idSetLog, "_SetOnLog")
	GUICtrlCreateGroup("", -99, -99, 1, 1)

	; Footer
	Local $idNote = GUICtrlCreateLabel(_T("set_autosave"), 15, 420, 250, 32)
	GUICtrlSetColor($idNote, 0x606060)
	GUICtrlSetOnEvent(GUICtrlCreateButton(_T("set_defaults"), $iW - 230, 415, 105, 28), "_SetOnDefaults")
	GUICtrlSetOnEvent(GUICtrlCreateButton(_T("set_close"), $iW - 115, 415, 105, 28), "_SettingsClose")

	; Native hotkey controls (keys are entered by pressing them)
	Local $hFont = GUICtrlSendMsg($idFontRef, $WM_GETFONT, 0, 0)
	$g_hSetHkToggle = _HotkeyCtrlCreate($iCtlX, 64, $iCtlW, 5001, $hFont, $g_sHkToggle)
	$g_hSetHkIn = _HotkeyCtrlCreate($iCtlX, 276, $iCtlW, 5002, $hFont, $g_sZoomIn)
	$g_hSetHkOut = _HotkeyCtrlCreate($iCtlX, 305, $iCtlW, 5003, $hFont, $g_sZoomOut)

	GUISetState(@SW_SHOW, $g_hSetGUI)
EndFunc

Func _SettingsClose()
	If Not $g_hSetGUI Then Return
	_SetOnSpeed()            ; take over an edited value that was not confirmed yet
	_SettingsApplyHotkeys()
	GUIDelete($g_hSetGUI)
	$g_hSetGUI = 0
	$g_hSetHkToggle = 0
	$g_hSetHkIn = 0
	$g_hSetHkOut = 0
	_RegisterToggleHotkey()
EndFunc

Func _SetOnLanguage()
	Local $sText = GUICtrlRead($g_idSetLang), $sSetting = "auto"
	For $i = 0 To UBound($g_aLangs) - 1
		If $g_aLangs[$i][$LANG_NAME] = $sText Then $sSetting = $g_aLangs[$i][$LANG_CODE]
	Next
	If $sSetting <> $g_sLangSetting Then _ApplyLanguage($sSetting)
EndFunc

Func _SetOnPanEnabled()
	$g_bPanEnabled = (BitAND(GUICtrlRead($g_idSetPanEnabled), $GUI_CHECKED) = $GUI_CHECKED)
	_SaveSettings()
EndFunc

Func _SetOnSpeed()
	If Not $g_hSetGUI Then Return
	Local $sText = StringReplace(StringStripWS(GUICtrlRead($g_idSetSpeed), $STR_STRIPLEADING + $STR_STRIPTRAILING), ",", ".")
	Local $fValue = Number($sText)
	If Not StringRegExp($sText, "^\d+(\.\d+)?$") Or $fValue < 0.1 Or $fValue > 5 Then
		MsgBox(48, $APP_TITLE, _T("set_speed_invalid"), 0, $g_hSetGUI)
		GUICtrlSetData($g_idSetSpeed, String($g_fSpeed))
		Return
	EndIf
	If $fValue <> $g_fSpeed Then
		$g_fSpeed = $fValue
		_SaveSettings()
	EndIf
EndFunc

Func _SetOnInvert()
	$g_iDir = (BitAND(GUICtrlRead($g_idSetInvert), $GUI_CHECKED) = $GUI_CHECKED) ? -1 : 1
	_SaveSettings()
EndFunc

Func _SetOnZoomEnabled()
	$g_bZoomEnabled = (BitAND(GUICtrlRead($g_idSetZoomEnabled), $GUI_CHECKED) = $GUI_CHECKED)
	$g_iWheelAcc = 0
	_SaveSettings()
EndFunc

Func _SetOnLog()
	$g_bLog = (BitAND(GUICtrlRead($g_idSetLog), $GUI_CHECKED) = $GUI_CHECKED)
	_SaveSettings()
EndFunc

Func _SetOnDefaults()
	If MsgBox(4 + 32, $APP_TITLE, _T("set_defaults_confirm"), 0, $g_hSetGUI) <> 6 Then Return
	$g_sHkToggle = $DEF_TOGGLE
	$g_bPanEnabled = True
	$g_fSpeed = $DEF_SPEED
	$g_iDir = 1
	$g_bZoomEnabled = True
	$g_sZoomIn = $DEF_ZOOM_IN
	$g_sZoomOut = $DEF_ZOOM_OUT
	$g_bLog = False
	_ApplyLanguage($DEF_LANGUAGE)   ; also saves the settings
	$g_bSetReopen = True            ; rebuild the dialog with the new values
EndFunc

; Read the three hotkey controls, validate and save. Called by the main loop after a change.
Func _SettingsApplyHotkeys()
	$g_bSetHkDirty = False
	If Not $g_hSetGUI Then Return

	; Enabled on/off shortcut: empty is allowed (no shortcut)
	Local $iRaw = _SendMessage($g_hSetHkToggle, $HKM_GETHOTKEY)
	If BitAND($iRaw, 0xFF) <> 0 Or $iRaw = 0 Then   ; ignore incomplete input (modifiers only)
		Local $sNew = _HotkeyCtrlGet($g_hSetHkToggle)
		If $iRaw <> 0 And $sNew = "" Then
			MsgBox(48, $APP_TITLE, _T("set_key_invalid"), 0, $g_hSetGUI)
			_HotkeyCtrlSet($g_hSetHkToggle, $g_sHkToggle)
		ElseIf $sNew <> $g_sHkToggle Then
			; test whether the shortcut is free; it is registered for real when the dialog closes
			If $sNew = "" Or HotKeySet($sNew, "_ToggleActive") Then
				If $sNew <> "" Then HotKeySet($sNew)
				$g_sHkToggle = $sNew
				_SaveSettings()
			Else
				MsgBox(48, $APP_TITLE, _T("hk_busy", _HotkeyName($sNew)), 0, $g_hSetGUI)
				_HotkeyCtrlSet($g_hSetHkToggle, $g_sHkToggle)
			EndIf
		EndIf
	EndIf

	_ApplyZoomKeyCtrl($g_hSetHkIn, $g_sZoomIn)
	_ApplyZoomKeyCtrl($g_hSetHkOut, $g_sZoomOut)
EndFunc

; Zoom keys: a key is required.
Func _ApplyZoomKeyCtrl($hCtrl, ByRef $sKey)
	Local $iRaw = _SendMessage($hCtrl, $HKM_GETHOTKEY)
	If $iRaw <> 0 And BitAND($iRaw, 0xFF) = 0 Then Return   ; incomplete input (modifiers only)
	Local $sNew = _HotkeyCtrlGet($hCtrl)
	If $sNew = "" Then
		MsgBox(48, $APP_TITLE, _T(($iRaw = 0) ? "set_key_empty" : "set_key_invalid"), 0, $g_hSetGUI)
		_HotkeyCtrlSet($hCtrl, $sKey)
		Return
	EndIf
	If $sNew <> $sKey Then
		$sKey = $sNew
		_SaveSettings()
	EndIf
EndFunc

; WM_COMMAND from the hotkey controls: remember the change, the main loop applies it.
Func _WM_COMMAND($hWnd, $iMsg, $wParam, $lParam)
	#forceref $iMsg
	If $g_hSetGUI And $hWnd = $g_hSetGUI Then
		Local $iCode = BitShift($wParam, 16)
		Local $hCtrl = HWnd($lParam)
		If ($hCtrl = $g_hSetHkToggle Or $hCtrl = $g_hSetHkIn Or $hCtrl = $g_hSetHkOut) And _
				($iCode = $EN_CHANGE_CODE Or $iCode = $EN_KILLFOCUS_CODE) Then $g_bSetHkDirty = True
	EndIf
	Return $GUI_RUNDEFMSG
EndFunc

; =============================================================================
; Hotkey control helpers (msctls_hotkey32 <-> AutoIt key notation)
; =============================================================================
Func _HotkeyCtrlCreate($iX, $iY, $iW, $iId, $hFont, $sKey)
	Local $hCtrl = _WinAPI_CreateWindowEx(0, "msctls_hotkey32", "", BitOR($WS_CHILD, $WS_VISIBLE, $WS_TABSTOP), $iX, $iY, $iW, 22, $g_hSetGUI, $iId)
	_SendMessage($hCtrl, $WM_SETFONT, $hFont, 1)
	_SendMessage($hCtrl, $HKM_SETRULES, 0, 0)   ; allow keys without modifiers (e.g. F3)
	_HotkeyCtrlSet($hCtrl, $sKey)
	Return $hCtrl
EndFunc

; Show an AutoIt key string ("^!p", "{F3}") in a hotkey control.
Func _HotkeyCtrlSet($hCtrl, $sKey)
	Local $iMods = 0
	While StringLen($sKey) > 1 And StringInStr("^!+#", StringLeft($sKey, 1))
		Switch StringLeft($sKey, 1)
			Case "^"
				$iMods = BitOR($iMods, $HOTKEYF_CONTROL)
			Case "!"
				$iMods = BitOR($iMods, $HOTKEYF_ALT)
			Case "+"
				$iMods = BitOR($iMods, $HOTKEYF_SHIFT)
		EndSwitch
		$sKey = StringTrimLeft($sKey, 1)
	WEnd
	Local $iVk = _SendKeyToVk($sKey)
	If _VkIsExtended($iVk) Then $iMods = BitOR($iMods, $HOTKEYF_EXT)
	_SendMessage($hCtrl, $HKM_SETHOTKEY, ($iVk = 0) ? 0 : BitOR($iVk, BitShift($iMods, -8)))
EndFunc

; Read a hotkey control as AutoIt key string; "" if empty or the key is not supported.
Func _HotkeyCtrlGet($hCtrl)
	Local $iRaw = _SendMessage($hCtrl, $HKM_GETHOTKEY)
	Local $iVk = BitAND($iRaw, 0xFF), $iMods = BitAND(BitShift($iRaw, 8), 0xFF)
	Local $sKey = _VkToSendKey($iVk)
	If $sKey = "" Then Return ""
	Local $sMods = ""
	If BitAND($iMods, $HOTKEYF_CONTROL) Then $sMods &= "^"
	If BitAND($iMods, $HOTKEYF_ALT) Then $sMods &= "!"
	If BitAND($iMods, $HOTKEYF_SHIFT) Then $sMods &= "+"
	Return $sMods & $sKey
EndFunc

; Virtual key code -> AutoIt Send/HotKeySet key name ("" = not supported).
Func _VkToSendKey($iVk)
	If $iVk >= 0x41 And $iVk <= 0x5A Then Return StringLower(Chr($iVk))
	If $iVk >= 0x30 And $iVk <= 0x39 Then Return Chr($iVk)
	If $iVk >= 0x70 And $iVk <= 0x87 Then Return "{F" & ($iVk - 0x6F) & "}"
	If $iVk >= 0x60 And $iVk <= 0x69 Then Return "{NUMPAD" & ($iVk - 0x60) & "}"
	Switch $iVk
		Case 0x08
			Return "{BS}"
		Case 0x09
			Return "{TAB}"
		Case 0x0D
			Return "{ENTER}"
		Case 0x20
			Return "{SPACE}"
		Case 0x21
			Return "{PGUP}"
		Case 0x22
			Return "{PGDN}"
		Case 0x23
			Return "{END}"
		Case 0x24
			Return "{HOME}"
		Case 0x25
			Return "{LEFT}"
		Case 0x26
			Return "{UP}"
		Case 0x27
			Return "{RIGHT}"
		Case 0x28
			Return "{DOWN}"
		Case 0x2D
			Return "{INS}"
		Case 0x2E
			Return "{DEL}"
		Case 0x6A
			Return "{NUMPADMULT}"
		Case 0x6B
			Return "{NUMPADADD}"
		Case 0x6D
			Return "{NUMPADSUB}"
		Case 0x6E
			Return "{NUMPADDOT}"
		Case 0x6F
			Return "{NUMPADDIV}"
	EndSwitch
	Return ""
EndFunc

; AutoIt key name -> virtual key code (0 = unknown).
Func _SendKeyToVk($sKey)
	For $iVk = 1 To 0xFE
		Local $sName = _VkToSendKey($iVk)
		If $sName <> "" And $sName = $sKey Then Return $iVk
	Next
	Return 0
EndFunc

; Keys that need the "extended" flag to be displayed correctly in a hotkey control.
Func _VkIsExtended($iVk)
	Return ($iVk >= 0x21 And $iVk <= 0x28) Or $iVk = 0x2D Or $iVk = 0x2E Or $iVk = 0x6F
EndFunc

; =============================================================================
; Language files
; =============================================================================

; Compiled exe: extract the embedded default language files if they are missing
; (existing files are not overwritten, so user edits are kept) and the gray tray icon.
Func _InstallEmbeddedFiles()
	If Not @Compiled Then Return
	DirCreate($LANG_DIR)
	FileInstall("lang\de.lng", $LANG_DIR & "\de.lng", $FC_NOOVERWRITE)
	FileInstall("lang\en.lng", $LANG_DIR & "\en.lng", $FC_NOOVERWRITE)
	FileInstall("SignMasterPan_off.ico", $ICON_OFF, $FC_OVERWRITE)
EndFunc

; Find all lang\*.lng files. Returns a 2D array [n][code, name, path].
Func _LangScan()
	Local $aLangs[0][3]
	Local $hSearch = FileFindFirstFile($LANG_DIR & "\*.lng")
	If $hSearch = -1 Then Return $aLangs
	While 1
		Local $sFile = FileFindNextFile($hSearch)
		If @error Then ExitLoop
		Local $sPath = $LANG_DIR & "\" & $sFile
		Local $sCode = "", $sName = ""
		_LangParse($sPath, $sCode, $sName, 0)
		If $sCode = "" Then $sCode = StringLower(StringTrimRight($sFile, 4))
		If $sName = "" Then $sName = $sCode
		Local $iRow = UBound($aLangs)
		ReDim $aLangs[$iRow + 1][3]
		$aLangs[$iRow][$LANG_CODE] = $sCode
		$aLangs[$iRow][$LANG_NAME] = $sName
		$aLangs[$iRow][$LANG_PATH] = $sPath
	WEnd
	FileClose($hSearch)
	Return $aLangs
EndFunc

; Read a language file: code and name from [Language], texts from [Strings] into $oStrings (optional).
Func _LangParse($sPath, ByRef $sCode, ByRef $sName, $oStrings)
	Local $hFile = FileOpen($sPath, $FO_READ + $FO_UTF8)
	If $hFile = -1 Then Return False
	Local $aLines = StringSplit(StringStripCR(FileRead($hFile)), @LF)
	FileClose($hFile)
	Local $sSection = ""
	For $i = 1 To $aLines[0]
		Local $sLine = StringStripWS($aLines[$i], $STR_STRIPLEADING + $STR_STRIPTRAILING)
		If $sLine = "" Or StringLeft($sLine, 1) = ";" Then ContinueLoop
		If StringLeft($sLine, 1) = "[" And StringRight($sLine, 1) = "]" Then
			$sSection = StringLower(StringMid($sLine, 2, StringLen($sLine) - 2))
			ContinueLoop
		EndIf
		Local $iEq = StringInStr($sLine, "=")
		If $iEq < 2 Then ContinueLoop
		Local $sKey = StringStripWS(StringLeft($sLine, $iEq - 1), $STR_STRIPTRAILING)
		Local $sValue = StringStripWS(StringMid($sLine, $iEq + 1), $STR_STRIPLEADING)
		Switch $sSection
			Case "language"
				If $sKey = "Code" Then $sCode = StringLower($sValue)
				If $sKey = "Name" Then $sName = $sValue
			Case "strings"
				If IsObj($oStrings) Then $oStrings.Item($sKey) = $sValue
		EndSwitch
	Next
	Return True
EndFunc

; Position of a language code in $g_aLangs, or -1.
Func _LangIndex($sCode)
	For $i = 0 To UBound($g_aLangs) - 1
		If $g_aLangs[$i][$LANG_CODE] = $sCode Then Return $i
	Next
	Return -1
EndFunc

; "auto" -> ISO 639 code of the Windows display language if a matching file exists, otherwise English.
Func _ResolveLang($sSetting)
	If $sSetting <> "auto" And _LangIndex($sSetting) >= 0 Then Return $sSetting
	Local $aUI = DllCall("kernel32.dll", "ushort", "GetUserDefaultUILanguage")
	If Not @error Then
		Local $aIso = DllCall("kernel32.dll", "int", "GetLocaleInfoW", "dword", $aUI[0], "dword", $LOCALE_SISO639LANGNAME, "wstr", "", "int", 16)
		If Not @error And _LangIndex(StringLower($aIso[3])) >= 0 Then Return StringLower($aIso[3])
	EndIf
	If _LangIndex($LANG_FALLBACK) >= 0 Then Return $LANG_FALLBACK
	If UBound($g_aLangs) > 0 Then Return $g_aLangs[0][$LANG_CODE]
	Return ""
EndFunc

; Load the texts of a language; English serves as fallback for missing keys.
Func _LangLoad($sCode)
	$g_sLang = $sCode
	$g_oStr.RemoveAll()
	$g_oStrFallback.RemoveAll()
	Local $sDummyCode = "", $sDummyName = ""
	Local $iFallback = _LangIndex($LANG_FALLBACK)
	If $iFallback >= 0 Then _LangParse($g_aLangs[$iFallback][$LANG_PATH], $sDummyCode, $sDummyName, $g_oStrFallback)
	Local $iLang = _LangIndex($sCode)
	If $iLang >= 0 Then _LangParse($g_aLangs[$iLang][$LANG_PATH], $sDummyCode, $sDummyName, $g_oStr)
EndFunc

; Text in the current language; %1..%4 are replaced, \n becomes a line break.
Func _T($sKey, $s1 = "", $s2 = "", $s3 = "", $s4 = "")
	Local $sText = $sKey
	If $g_oStr.Exists($sKey) Then
		$sText = $g_oStr.Item($sKey)
	ElseIf $g_oStrFallback.Exists($sKey) Then
		$sText = $g_oStrFallback.Item($sKey)
	EndIf
	$sText = StringReplace($sText, "\n", @CRLF)
	$sText = StringReplace($sText, "%1", $s1)
	$sText = StringReplace($sText, "%2", $s2)
	$sText = StringReplace($sText, "%3", $s3)
	$sText = StringReplace($sText, "%4", $s4)
	Return $sText
EndFunc

; Switch the language (setting "auto" or a code), save it and refresh tray and dialog.
Func _ApplyLanguage($sSetting)
	$g_sLangSetting = $sSetting
	_LangLoad(_ResolveLang($sSetting))
	_SaveSettings()
	_UpdateTrayTexts()
	If $g_hSetGUI Then $g_bSetReopen = True
EndFunc

; =============================================================================
; Helper functions
; =============================================================================
Func _ModifierDown()
	Return _IsPressed("10") Or _IsPressed("11") Or _IsPressed("12") Or _IsPressed("5B") Or _IsPressed("5C")
EndFunc

Func _ShowHelp()
	Local $sHk = ($g_sHkToggle = "") ? "-" : _HotkeyName($g_sHkToggle)
	MsgBox(64, $APP_TITLE, _T("help", $sHk, _KeyName($g_sZoomIn), _KeyName($g_sZoomOut), $INI))
EndFunc

; "{F3}" -> "F3"
Func _KeyName($sKey)
	Return StringRegExpReplace($sKey, "[{}]", "")
EndFunc

; "^!+h" -> "Ctrl+Alt+Shift+H" (Ctrl name taken from the language file)
Func _HotkeyName($sHk)
	Local $sName = ""
	While StringLen($sHk) > 1 And StringInStr("^!+#", StringLeft($sHk, 1))
		Switch StringLeft($sHk, 1)
			Case "^"
				$sName &= _T("key_ctrl") & "+"
			Case "!"
				$sName &= "Alt+"
			Case "+"
				$sName &= "Shift+"
			Case "#"
				$sName &= "Win+"
		EndSwitch
		$sHk = StringTrimLeft($sHk, 1)
	WEnd
	Return $sName & StringUpper(_KeyName($sHk))
EndFunc

Func _BarText($aBar)
	If Not IsArray($aBar) Then Return "-"
	Return $aBar[$BAR_HWND] & "(len " & $aBar[$BAR_LEN] & " thumb " & $aBar[$BAR_THUMB] & "+" & $aBar[$BAR_THUMBLEN] & ")"
EndFunc

Func _Log($s)
	If $g_bLog Then FileWriteLine($LOG, @HOUR & ":" & @MIN & ":" & @SEC & "." & @MSEC & " " & $s)
EndFunc

Func _SelfTest()
	Local $hMain = WinGetHandle("[CLASS:" & $SM_MAIN_CLASS & "]")
	$g_hDoc = ControlGetHandle($hMain, "", "[CLASS:" & $SM_DOC_CLASS & "]")
	_Log("Selftest main=" & $hMain & " doc=" & $g_hDoc)
	_PanBegin()
	For $i = 1 To 20
		_PanApply(-10, -6)
		Sleep(30)
	Next
	_Log("Selftest end")
EndFunc

Func _Exit()
	Exit
EndFunc

Func _Cleanup()
	If $g_hHook Then _WinAPI_UnhookWindowsHookEx($g_hHook)
	DllCallbackFree($g_hHookProc)
EndFunc
