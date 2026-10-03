@echo off
rem Doble clic para subir los cambios de MANUAL IA a GitHub.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0actualizar_github.ps1" %*
