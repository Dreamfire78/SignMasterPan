@echo off
rem Builds SignMasterPan.exe (32-bit, no UPX, with icon and embedded language files) from SignMasterPan.au3.
rem Quit a running SignMasterPan.exe via its tray menu first.
cd /d "%~dp0"
"AutoIt\Aut2Exe\Aut2exe.exe" /in "SignMasterPan.au3" /out "SignMasterPan.exe" /icon "SignMasterPan.ico" /x86 /nopack /comp 2
if exist "SignMasterPan.exe" (echo SignMasterPan.exe created.) else (echo Build failed.)
