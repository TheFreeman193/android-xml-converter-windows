@echo off

IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    SET "lcmd=%ProgramFiles%\PowerShell\7\pwsh.exe"
) ELSE IF EXIST "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe" (
    SET "lcmd=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
) ELSE IF EXIST "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
    SET "lcmd=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
) ELSE IF EXIST "%windir%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" (
    SET "lcmd=%windir%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
) ELSE (
    echo "No suitable PowerShell executable was found!"
    (CALL)
    GOTO end
)

"%lcmd%" -nop -nol -ex bypass -File Build-Windows.ps1 %*

:end
IF /I %0 EQU "%~dpnx0" pause
exit /b %ERRORLEVEL%
