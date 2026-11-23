@echo off
chcp 65001 >nul
setlocal

set "GODOT=D:\GodotWorkspace\engine\Godot_v4.7.2-stable_win64_console.exe"
set "PROJ=D:\GodotWorkspace\projects\ArrowArena"
set "OUT_DIR=D:\GodotWorkspace\builds\windows"
set "OUT_EXE=%OUT_DIR%\AI娘像素大乱斗.exe"
set "TPL=%APPDATA%\Godot\export_templates\4.7.2.stable\windows_release_x86_64.exe"

echo ========================================================
echo   AI 娘像素大乱斗 · 一键打包独立 Windows 绿色版 (.exe)
echo ========================================================

if not exist "%TPL%" (
    echo [提示] 未检测到 Windows 导出模板：
    echo   %TPL%
    echo 请在 Godot 编辑器点击：编辑器 -^> 管理导出模板 -^> 下载并安装 (4.7.2.stable)
    echo 或运行 D:\msys64\ucrt64\bin\python.exe D:\GodotWorkspace\downloads\download_web_entry.py windows_release_x86_64.exe "%APPDATA%\Godot\export_templates\4.7.2.stable"
    pause
    exit /b 1
)

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
echo 正在打包独立单文件绿色版...
"%GODOT%" --headless --path "%PROJ%" --export-release "Windows Desktop" "%OUT_EXE%"
if errorlevel 1 (
    echo [失败] 导出过程中出错，请查看上方日志。
    pause
    exit /b 1
)

echo.
echo [成功] 独立绿色版已生成：
echo   %OUT_EXE%
echo 直接把该 .exe 文件发给局域网朋友双击即可开黑！（无需安装 Godot）
pause
