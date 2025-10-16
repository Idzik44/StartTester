@echo off
setlocal

REM === Repo root = folder, w którym leży ten .bat ===
set "REPO=%~dp0"

REM --- sprawdź, czy są skrypty PowerShell ---
if not exist "%REPO%tools\mirror-to-utf8.ps1" (
  echo [ERROR] Brak pliku: tools\mirror-to-utf8.ps1
  echo        Skopiuj go do tools\ i sprobuj ponownie.
  goto :end
)
if not exist "%REPO%tools\build-utf8-links.ps1" (
  echo [ERROR] Brak pliku: tools\build-utf8-links.ps1
  echo        Skopiuj go do tools\ i sprobuj ponownie.
  goto :end
)

REM --- wykonaj mirror do docs/utf8 ---
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%tools\mirror-to-utf8.ps1"
if errorlevel 1 goto :end

REM --- zbuduj listę RAW linków ---
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%tools\build-utf8-links.ps1"

REM --- podgląd listy (opcjonalnie otworzy w domyślnym edytorze) ---
if exist "%REPO%docs\UTF8_LINKS.md" start "" "%REPO%docs\UTF8_LINKS.md"

:end
endlocal
