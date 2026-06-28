@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

REM ==================================================
REM 設定
REM ==================================================
set "REPO_DIR=C:\Users\user\ClimaxGit\climax5"
set "PYTHON_EXE=python"

set "SCRIPT_TORECA=%REPO_DIR%\scrape_torecabirth_pk_purchase.py"
set "SCRIPT_CARDRUSH=%REPO_DIR%\update_buy_price_from_cardrush.py"
set "SCRIPT_LOUNGE_PSA10=%REPO_DIR%\scrape_toreca_lounge_psa10.py"
set "SCRIPT_LOUNGE_BOX=%REPO_DIR%\scrape_toreca_lounge_box_and_merge.py"
set "SCRIPT_CSV=%REPO_DIR%\export_sheet1_to_csv.py"
set "BUILD_SCRIPT=gen_buylist.py"

set "DOCS_DEFAULT=docs\default"
set "DOCS_ROOT=docs"
set "DOCS_PRICE_ASC=docs\price_asc"
set "DOCS_PRICE_DESC=docs\price_desc"

set "GAZOU_DIR=gazou"
set "DOCS_GAZOU_DIR=docs\gazou"

REM ==================================================
REM BOX / PSA tools
REM ==================================================
set "BOX_TOOLS_DIR=%REPO_DIR%\box_tools"

set "BOX_GEN_SCRIPT=%BOX_TOOLS_DIR%\generate_box_buylist.py"
set "BOX_RENDER_SCRIPT=%BOX_TOOLS_DIR%\render_box_buylist_png.py"

set "BOX_OUT_HTML_DIR=%REPO_DIR%\docs\box"
set "BOX_HTML_PATH=%BOX_OUT_HTML_DIR%\index.html"
set "BOX_OUT_DIR=%BOX_TOOLS_DIR%\out_png"

set "PSA_GEN_SCRIPT=%BOX_TOOLS_DIR%\generate_psa_buylist.py"
set "PSA_RENDER_SCRIPT=%BOX_TOOLS_DIR%\html_to_png.py"
set "PSA_OUT_HTML_DIR=%REPO_DIR%\docs\psa"
set "PSA_HTML_PATH=%PSA_OUT_HTML_DIR%\index.html"
set "PSA_OUT_DIR=%BOX_TOOLS_DIR%\out_png_psa"

REM PNG保存先も英数字フォルダ
REM PNG保存先
set "PNG_SAVE_DIR=C:\Users\user\OneDrive\ドキュメント\Desktop\ポケカラッシュ"
REM ==================================================
REM ログ設定
REM ==================================================
set "LOG_DIR=%REPO_DIR%\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

for /f "tokens=1-3 delims=/ " %%a in ("%date%") do set "D=%%a%%b%%c"
for /f "tokens=1-3 delims=:." %%a in ("%time%") do set "T=%%a%%b%%c"
set "T=%T: =0%"
set "LOG_FILE=%LOG_DIR%\run_%D%_%T%.log"

echo ================================================== > "%LOG_FILE%"
echo START: %date% %time%>> "%LOG_FILE%"
echo BAT: %~f0>> "%LOG_FILE%"
echo ==================================================>> "%LOG_FILE%"

echo.
echo [INFO] ログ: %LOG_FILE%
echo.

call :LOG "===== ENV ====="
call :LOG "REPO_DIR=%REPO_DIR%"
call :LOG "PYTHON_EXE=%PYTHON_EXE%"
call :LOG "BOX_TOOLS_DIR=%BOX_TOOLS_DIR%"
call :LOG "BOX_HTML_PATH=%BOX_HTML_PATH%"
call :LOG "PSA_HTML_PATH=%PSA_HTML_PATH%"
call :LOG "PNG_SAVE_DIR=%PNG_SAVE_DIR%"
call :LOG "LOG_FILE=%LOG_FILE%"
call :LOG "==============="

REM ==================================================
REM 事前フォルダ準備
REM ==================================================
if not exist "%PNG_SAVE_DIR%\" mkdir "%PNG_SAVE_DIR%" >> "%LOG_FILE%" 2>&1
if not exist "%BOX_OUT_HTML_DIR%\" mkdir "%BOX_OUT_HTML_DIR%" >> "%LOG_FILE%" 2>&1
if not exist "%BOX_OUT_DIR%\" mkdir "%BOX_OUT_DIR%" >> "%LOG_FILE%" 2>&1
if not exist "%PSA_OUT_HTML_DIR%\" mkdir "%PSA_OUT_HTML_DIR%" >> "%LOG_FILE%" 2>&1
if not exist "%PSA_OUT_DIR%\" mkdir "%PSA_OUT_DIR%" >> "%LOG_FILE%" 2>&1

REM ==================================================
REM メイン処理
REM ==================================================
call :RUN cd /d "%REPO_DIR%"

call :RUN "%PYTHON_EXE%" "%SCRIPT_TORECA%"
call :RUN "%PYTHON_EXE%" "%SCRIPT_CARDRUSH%"
call :RUN "%PYTHON_EXE%" "%SCRIPT_LOUNGE_PSA10%"
call :RUN "%PYTHON_EXE%" "%SCRIPT_LOUNGE_BOX%"
call :RUN "%PYTHON_EXE%" "%SCRIPT_CSV%"
call :RUN "%PYTHON_EXE%" "%BUILD_SCRIPT%"

REM ==================================================
REM EXTRA: BOX
REM Git push前に生成する
REM ==================================================
call :LOG "===== [EXTRA] BOX START ====="

if not exist "%BOX_GEN_SCRIPT%" (
  call :LOG "[WARN] BOX生成スキップ: %BOX_GEN_SCRIPT% が見つかりません"
  goto :AFTER_BOX
)

if not exist "%BOX_RENDER_SCRIPT%" (
  call :LOG "[WARN] BOX PNG生成スキップ: %BOX_RENDER_SCRIPT% が見つかりません"
  goto :AFTER_BOX
)

if exist "%BOX_OUT_DIR%\*.png" (
  del /q "%BOX_OUT_DIR%\*.png" >> "%LOG_FILE%" 2>&1
)

pushd "%BOX_TOOLS_DIR%" >> "%LOG_FILE%" 2>&1

call :RUN "%PYTHON_EXE%" "%BOX_GEN_SCRIPT%" --out "%BOX_OUT_HTML_DIR%"
call :RUN "%PYTHON_EXE%" "%BOX_RENDER_SCRIPT%" --html "%BOX_HTML_PATH%" --out "%BOX_OUT_DIR%"

popd >> "%LOG_FILE%" 2>&1

if exist "%BOX_OUT_DIR%\buylist_page_1.png" (
  copy /y "%BOX_OUT_DIR%\buylist_page_1.png" "%PNG_SAVE_DIR%\ポケカBOX買取表1.png" >> "%LOG_FILE%" 2>&1
)

if exist "%BOX_OUT_DIR%\buylist_page_2.png" (
  copy /y "%BOX_OUT_DIR%\buylist_page_2.png" "%PNG_SAVE_DIR%\ポケカBOX買取表2.png" >> "%LOG_FILE%" 2>&1
)

:AFTER_BOX
call :LOG "===== [EXTRA] BOX END ====="

REM ==================================================
REM EXTRA: PSA
REM Git push前に生成する
REM ==================================================
call :LOG "===== [EXTRA] PSA START ====="

if not exist "%PSA_GEN_SCRIPT%" (
  call :LOG "[WARN] PSA生成スキップ: %PSA_GEN_SCRIPT% が見つかりません"
  goto :AFTER_PSA
)

if not exist "%PSA_RENDER_SCRIPT%" (
  call :LOG "[WARN] PSA PNG生成スキップ: %PSA_RENDER_SCRIPT% が見つかりません"
  goto :AFTER_PSA
)

if exist "%PSA_OUT_DIR%\*.png" (
  del /q "%PSA_OUT_DIR%\*.png" >> "%LOG_FILE%" 2>&1
)

pushd "%BOX_TOOLS_DIR%" >> "%LOG_FILE%" 2>&1

call :RUN "%PYTHON_EXE%" "%PSA_GEN_SCRIPT%" --out "%PSA_OUT_HTML_DIR%"
call :RUN "%PYTHON_EXE%" "%PSA_RENDER_SCRIPT%" --html "%PSA_HTML_PATH%" --out "%PSA_OUT_DIR%" --scale 2.0

popd >> "%LOG_FILE%" 2>&1

set "N=1"
for %%F in ("%PSA_OUT_DIR%\buylist_page_*.png") do (
  if exist "%%~fF" (
    copy /y "%%~fF" "%PNG_SAVE_DIR%\pokemon_psa_buylist_!N!.png" >> "%LOG_FILE%" 2>&1
    set /a N+=1
  )
)

:AFTER_PSA
call :LOG "===== [EXTRA] PSA END ====="

REM ==================================================
REM Git反映
REM BOX/PSA生成後に add / commit / push
REM ==================================================
call :RUN git status

REM WEB買取表を全部Gitに反映
call :RUN git add docs

REM bat自体もGit管理している場合は反映
if exist "run_buy_update_all.bat" (
  call :RUN git add "run_buy_update_all.bat"
)

REM 画像保存先はGit外なのでgit addしない
call :LOG "[INFO] PNG_SAVE_DIR is outside git, skip git add"

REM commit は変更なしのとき失敗扱いになるので止めない
call :LOG "===== git commit (no-fail) ====="
git commit -m "update buylist, csv, and pages" >> "%LOG_FILE%" 2>&1
set "COMMIT_RC=%ERRORLEVEL%"
if not "%COMMIT_RC%"=="0" (
  call :LOG "[INFO] git commit skipped or no changes. RC=%COMMIT_RC%"
)

call :RUN git push origin main

call :LOG "===== DONE ====="

echo.
echo =====================================
echo 完了 / ログを開きます
echo LOG_FILE=%LOG_FILE%
echo =====================================
echo.

start "" notepad "%LOG_FILE%"
echo.
echo 終了しました。閉じるには何かキーを押してください。
pause
endlocal
exit /b 0

REM ==================================================
REM サブルーチン
REM ==================================================
:LOG
echo %~1
echo %~1>> "%LOG_FILE%"
exit /b 0

:UPDATE_DATE
"%PYTHON_EXE%" -c "from pathlib import Path; import re, datetime; p=Path(r'%~1'); s=p.read_text(encoding='utf-8'); today=datetime.datetime.now().strftime('%Y/%m/%d'); today_jp=datetime.datetime.now().strftime('%Y年%m月%d日'); s=re.sub(r'\d{4}[/-]\d{1,2}[/-]\d{1,2}', today, s); s=re.sub(r'\d{4}年\d{1,2}月\d{1,2}日', today_jp, s); p.write_text(s,encoding='utf-8')" >> "%LOG_FILE%" 2>&1
if not "%ERRORLEVEL%"=="0" (
  call :LOG "[ERROR] 日付更新に失敗: %~1"
  pause
  exit /b 1
)
call :LOG "[INFO] 日付更新OK: %~1"
exit /b 0



:RUN
echo [RUN] %*>> "%LOG_FILE%"
%* >> "%LOG_FILE%" 2>&1
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo [ERROR] RC=%RC% at %*>> "%LOG_FILE%"
  echo.
  echo [ERROR] 失敗しました: %*
  echo ログを開きます: %LOG_FILE%
  start "" notepad "%LOG_FILE%"
  echo.
  pause
  exit /b %RC%
)
exit /b 0