@echo off
:: =================================================================
::  YSO - Your System Optimizer 1.0 - launcher
::  Double-click this file to open YSO without installing it
::  (YSO.ps1 must be in the same folder). YSO asks for administrator
::  rights. To install it instead, see install.ps1.
::
::  Optional:  YSO.bat -DryRun   (analyze only, delete nothing)
:: =================================================================
setlocal
set "YSO=%~dp0YSO.ps1"

if not exist "%YSO%" (
    echo.
    echo  [!] YSO.ps1 was not found next to this file.
    echo      Keep YSO.bat and YSO.ps1 in the same folder.
    echo.
    echo  [!] YSO.ps1 est introuvable a cote de ce fichier.
    echo      Gardez YSO.bat et YSO.ps1 dans le meme dossier.
    echo.
    pause
    exit /b 1
)

:: YSO needs Windows PowerShell 5.1: the exit code below is its version (51 = 5.1).
powershell.exe -NoProfile -NonInteractive -Command "exit ($PSVersionTable.PSVersion.Major * 10 + $PSVersionTable.PSVersion.Minor)" >nul 2>&1
set "PSV=%ERRORLEVEL%"
if %PSV% GEQ 51 goto run
echo.
echo  [!] YSO needs Windows PowerShell 5.1 (Windows 10 version 1607 or later, or Windows 11).
echo      This PC does not have it, or PowerShell is blocked here. Nothing was changed.
echo.
echo  [!] YSO a besoin de Windows PowerShell 5.1 (Windows 10 version 1607 ou plus, ou Windows 11).
echo      Ce PC ne l'a pas, ou PowerShell y est bloque. Rien n'a ete modifie.
echo.
pause
exit /b 1

:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%YSO%" %*
set "RC=%ERRORLEVEL%"
:: 0 = normal end, 3 = YSO already explained why it stopped.
if "%RC%"=="0" goto done
if "%RC%"=="3" goto done
echo.
echo  [!] YSO stopped unexpectedly (code %RC%).
echo      On a PC managed by a school or company, scripts may be blocked.
echo      Otherwise, start YSO again and use All tools ^> Report a problem.
echo.
echo  [!] YSO s'est arrete de facon inattendue (code %RC%).
echo      Sur un PC gere par une ecole ou une entreprise, les scripts sont peut-etre bloques.
echo      Sinon, relancez YSO et utilisez Tous les outils ^> Signaler un probleme.
echo.
pause

:done
endlocal
