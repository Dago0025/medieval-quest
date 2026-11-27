; Installer di Medieval Quest (NSIS 3, Modern UI 2).
; Non si compila a mano: lo prepara e lo compila installer/prepara_installer.py, che crea la cartella payload/
; (eseguibile, guida e licenze) e passa versione e percorsi con /D.
;   makensis /DVERSIONE=2026.11.20 /DPAYLOAD=<cartella> /DUSCITA=<file.exe> /DICONA=<file.ico> /DAVVISO=<file.txt> medieval_quest.nsi

Unicode true
SetCompressor /SOLID lzma
SetCompressorDictSize 64

!ifndef VERSIONE
  !define VERSIONE "0.0.0"
!endif
!ifndef VIVERSIONE
  !define VIVERSIONE "${VERSIONE}.0"   ; 4 numeri (prepara_installer.py la passa gia' completa)
!endif
!define NOME "Medieval Quest"
!define EDITORE "Federico Deserti (progetto amatoriale)"
!define CHIAVE_DISINST "Software\Microsoft\Windows\CurrentVersion\Uninstall\MedievalQuest"

Name "${NOME}"
OutFile "${USCITA}"
InstallDir "$LOCALAPPDATA\Programs\${NOME}"
InstallDirRegKey HKCU "Software\MedievalQuest" "Cartella"
RequestExecutionLevel user
ShowInstDetails show
BrandingText "${NOME} ${VERSIONE}"

VIProductVersion "${VIVERSIONE}"
VIAddVersionKey /LANG=0 "ProductName" "${NOME}"
VIAddVersionKey /LANG=0 "ProductVersion" "${VERSIONE}"
VIAddVersionKey /LANG=0 "FileVersion" "${VERSIONE}"
VIAddVersionKey /LANG=0 "FileDescription" "Installer di ${NOME}"
VIAddVersionKey /LANG=0 "LegalCopyright" "Codice MIT. Contenuti di terzi dei rispettivi titolari."
VIAddVersionKey /LANG=0 "CompanyName" "${EDITORE}"

!include "MUI2.nsh"

!define MUI_ICON "${ICONA}"
!define MUI_UNICON "${ICONA}"
!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${AVVISO}"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\${NOME}.exe"
!define MUI_FINISHPAGE_SHOWREADME "$INSTDIR\Guida di gioco.html"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Italian"
!insertmacro MUI_LANGUAGE "English"

Section "!${NOME}" SecGioco
  SectionIn RO
  SetOutPath "$INSTDIR"
  ; dal 26/11/2026 il gioco non usa piu' file dell'originale: si toglie la cartella delle versioni precedenti
  RMDir /r "$INSTDIR\originale"
  File /r "${PAYLOAD}\*.*"

  WriteRegStr HKCU "Software\MedievalQuest" "Cartella" "$INSTDIR"
  WriteUninstaller "$INSTDIR\Disinstalla.exe"
  WriteRegStr HKCU "${CHIAVE_DISINST}" "DisplayName" "${NOME}"
  WriteRegStr HKCU "${CHIAVE_DISINST}" "DisplayVersion" "${VERSIONE}"
  WriteRegStr HKCU "${CHIAVE_DISINST}" "Publisher" "${EDITORE}"
  WriteRegStr HKCU "${CHIAVE_DISINST}" "DisplayIcon" "$INSTDIR\${NOME}.exe"
  WriteRegStr HKCU "${CHIAVE_DISINST}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${CHIAVE_DISINST}" "UninstallString" '"$INSTDIR\Disinstalla.exe"'
  WriteRegDWORD HKCU "${CHIAVE_DISINST}" "NoModify" 1
  WriteRegDWORD HKCU "${CHIAVE_DISINST}" "NoRepair" 1

  CreateDirectory "$SMPROGRAMS\${NOME}"
  CreateShortcut "$SMPROGRAMS\${NOME}\${NOME}.lnk" "$INSTDIR\${NOME}.exe"
  CreateShortcut "$SMPROGRAMS\${NOME}\Guida di gioco.lnk" "$INSTDIR\Guida di gioco.html"
  CreateShortcut "$SMPROGRAMS\${NOME}\Crediti e diritti.lnk" "$INSTDIR\Crediti e diritti.html"
  CreateShortcut "$SMPROGRAMS\${NOME}\Disinstalla ${NOME}.lnk" "$INSTDIR\Disinstalla.exe"
SectionEnd

Section "Collegamento sul desktop" SecDesktop
  CreateShortcut "$DESKTOP\${NOME}.lnk" "$INSTDIR\${NOME}.exe"
SectionEnd

LangString DESC_GIOCO ${LANG_ITALIAN} "Il gioco, la guida e le licenze (obbligatorio)."
LangString DESC_GIOCO ${LANG_ENGLISH} "The game, the guide and the licenses (required)."
LangString DESC_DESKTOP ${LANG_ITALIAN} "Un collegamento al gioco sul desktop."
LangString DESC_DESKTOP ${LANG_ENGLISH} "A shortcut to the game on the desktop."
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecGioco} $(DESC_GIOCO)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} $(DESC_DESKTOP)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Function .onInit
  !insertmacro MUI_LANGDLL_DISPLAY
FunctionEnd

; La disinstallazione toglie solo i file del gioco: salvataggi e impostazioni
; (%APPDATA%\Godot\app_userdata\MTW Remake) restano.
Section "Uninstall"
  RMDir /r "$INSTDIR\originale"
  Delete "$INSTDIR\${NOME}.exe"
  Delete "$INSTDIR\Guida di gioco.html"
  Delete "$INSTDIR\Crediti e diritti.html"
  Delete "$INSTDIR\LEGGIMI.txt"
  Delete "$INSTDIR\LICENSE.txt"
  Delete "$INSTDIR\LICENZE_TERZE_PARTI.txt"
  Delete "$INSTDIR\Disinstalla.exe"
  RMDir "$INSTDIR"

  Delete "$DESKTOP\${NOME}.lnk"
  RMDir /r "$SMPROGRAMS\${NOME}"
  DeleteRegKey HKCU "${CHIAVE_DISINST}"
  DeleteRegKey HKCU "Software\MedievalQuest"
SectionEnd

Function un.onInit
  !insertmacro MUI_UNGETLANGUAGE
FunctionEnd
