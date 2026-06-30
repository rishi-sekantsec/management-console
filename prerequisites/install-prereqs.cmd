@echo off
setlocal
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-prereqs.ps1" %*
