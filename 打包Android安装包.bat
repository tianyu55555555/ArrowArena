@echo off
chcp 65001 >nul
setlocal

set "GODOT=D:\GodotWorkspace\engine\Godot_v4.7.2-stable_win64_console.exe"
set "PROJ=D:\GodotWorkspace\projects\ArrowArena"
set "OUT_DIR=D:\GodotWorkspace\builds\android"
set "OUT_APK=%OUT_DIR%\AI娘像素大乱斗.apk"

set "JAVA_HOME=D:\GodotWorkspace\android-tools\jdk17"
set "ANDROID_HOME=D:\GodotWorkspace\android-sdk"
set "PATH=%JAVA_HOME%\bin;%ANDROID_HOME%\build-tools\36.0.0;%ANDROID_HOME%\platform-tools;%PATH%"

if exist "%PROJ%\android_sign.local.bat" (
    call "%PROJ%\android_sign.local.bat"
)

echo ========================================================
echo   AI 娘像素大乱斗 · 一键打包安卓手机安装包 (.apk)
echo ========================================================

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
echo 正在导出并签名 Android ARM64 安装包...
"%GODOT%" --headless --path "%PROJ%" --export-release "Android" "%OUT_APK%"
if errorlevel 1 (
    echo [失败] 导出过程中出错，请查看上方日志。
    pause
    exit /b 1
)

echo.
echo [成功] 已签名安卓安装包已生成：
echo   %OUT_APK%
echo 把 .apk 发到安卓手机安装即可畅玩（支持与 Windows 电脑同 Wi-Fi 局域网联机！）
pause
