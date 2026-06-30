@echo off
setlocal
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
