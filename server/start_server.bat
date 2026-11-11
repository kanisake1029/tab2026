@echo off
chcp 65001 > nul
title TAB 2026 AI寸評サーバー
cd /d "%~dp0"
node server.js
pause
