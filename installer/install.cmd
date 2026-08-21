@echo off
rem ============================================================================
rem  Genius Assistant - Instalador (doble clic)
rem
rem  Corre _genius-setup.ps1 con Invoke-Expression (como COMANDOS, no como
rem  archivo .ps1). La Execution Policy de PowerShell aplica a ARCHIVOS de script,
rem  no a comandos por -Command/IEX -> este metodo funciona aunque el equipo tenga
rem  scripts bloqueados (Restricted/AllSigned), incluso por GPO de dominio, y SIN
rem  permisos de administrador. GENIUS_SCRIPT_DIR le dice al instalador donde estan
rem  el zip, el token y adversary.md.
rem ============================================================================
setlocal
cd /d "%~dp0"
set "GENIUS_SCRIPT_DIR=%~dp0"

echo Instalando Genius Assistant...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Get-Content -Raw -Encoding UTF8 -LiteralPath '_genius-setup.ps1')"

echo.
echo Si ves 'Instalacion completada' arriba, ya quedo. Abre Genius Assistant desde el menu Inicio.
pause
