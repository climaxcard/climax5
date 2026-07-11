@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"

REM ============================================================
REM POKEMON buylist update + SAFE deploy
REM - UTF-8 no BOM recommended
REM - Never sync S3 root
REM - Never use S3 --delete
REM - External JSON mode: upload buylist.json
REM - Embedded HTML mode: upload index.html only
REM ============================================================

set "ROOT=C:\Users\user\ClimaxGit\climax5"
set "SCRIPTS=%ROOT%\scripts"
set "PYTHON_EXE=python"

set "DOCS_DIR=%ROOT%\docs"
set "SCRIPTS_DOCS_DIR=%SCRIPTS%\docs"
set "INDEX_HTML="
set "BUYLIST_JSON="
set "NEEDS_JSON=0"

set "S3_BUCKET=climax-kaitori-static"
set "S3_PREFIX=pokemon"
set "CF_DIST_ID=E51XRDVR8AQAD"
set "PUBLIC_URL=https://kaitori.climax-card.com/pokemon/default/"

REM EC2 sync settings
set "EC2_KEY=C:\Users\user\OneDrive\ドキュメント\Desktop\絶対消さないで\climax-kaitori-linux.pem"
set "EC2_HOST=ec2-user@52.195.218.55"
set "EC2_DIR=/home/ec2-user/climax5"

REM Myca CSV is stored in the repository for Windows and EC2 compatibility
set "OUTPUT_DIR=%ROOT%"
set "MYCA_CSV_OUT=%ROOT%"
set "MYCA_CSV_NAME=pokemon_myca_upload.csv"
set "MYCA_CSV_PATH=%MYCA_CSV_OUT%\%MYCA_CSV_NAME%"
set "XLSM="

set "LOG_DIR=%ROOT%\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1
set "LOG_FILE=%LOG_DIR%\safe_pokemon_update_final.log"

> "%LOG_FILE%" echo ===== POKEMON SAFE UPDATE START %date% %time% =====

call :CHECK_TOOL "%PYTHON_EXE%" || goto :END_FAIL
call :CHECK_TOOL git || goto :END_FAIL
call :CHECK_TOOL aws || goto :END_FAIL

if not exist "%ROOT%" call :DIE "ROOT not found: %ROOT%"
if not exist "%DOCS_DIR%" mkdir "%DOCS_DIR%" >> "%LOG_FILE%" 2>&1
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%" >> "%LOG_FILE%" 2>&1

call :RESOLVE_XLSM

call :LOG "[0/9] Optional git pull"
cd /d "%ROOT%" || call :DIE "cd failed: %ROOT%"
call :SAFE_GIT_PULL

call :LOG "[0.5/9] Python dependencies"
call :RUN "%PYTHON_EXE%" -m pip install -q beautifulsoup4 pandas openpyxl requests pillow lxml playwright

call :LOG "[1/9] Main update scripts"
cd /d "%ROOT%" || call :DIE "cd failed: %ROOT%"
call :LOG "[INFO] No required main scripts set."

call :LOG "[2/9] Optional update scripts"
cd /d "%ROOT%" || call :DIE "cd failed: %ROOT%"
if exist "%ROOT%\scrape_torecabirth_pk_purchase.py" (
  call :RUN "%PYTHON_EXE%" "%ROOT%\scrape_torecabirth_pk_purchase.py"
) else (
  call :LOG "[WARN] Missing optional script. Skip: scrape_torecabirth_pk_purchase.py"
)
if exist "%ROOT%\update_buy_price_from_cardrush.py" (
  call :RUN "%PYTHON_EXE%" "%ROOT%\update_buy_price_from_cardrush.py"
) else (
  call :LOG "[WARN] Missing optional script. Skip: update_buy_price_from_cardrush.py"
)
if exist "%ROOT%\scrape_toreca_lounge_box_and_merge.py" (
  call :RUN "%PYTHON_EXE%" "%ROOT%\scrape_toreca_lounge_box_and_merge.py"
) else (
  call :LOG "[WARN] Missing optional script. Skip: scrape_toreca_lounge_box_and_merge.py"
)
if exist "%ROOT%\scrape_toreca_lounge_psa10.py" (
  call :RUN "%PYTHON_EXE%" "%ROOT%\scrape_toreca_lounge_psa10.py"
) else (
  call :LOG "[WARN] Missing optional script. Skip: scrape_toreca_lounge_psa10.py"
)
if exist "%ROOT%\export_sheet1_to_csv.py" (
  if not defined XLSM call :DIE "buylist.xlsm was not resolved."
  call :RUN "%PYTHON_EXE%" "%ROOT%\export_sheet1_to_csv.py" --file-path "%XLSM%" --output "%MYCA_CSV_PATH%" --sheet-name "シート1"
  if not exist "%MYCA_CSV_PATH%" call :DIE "Myca CSV was not created: %MYCA_CSV_PATH%"
  call :LOG "[OK] Myca CSV=%MYCA_CSV_PATH%"
) else (
  call :DIE "Missing required script: export_sheet1_to_csv.py"
)

call :LOG "[3/9] Build static pages"
set "BUILD_DONE="
if not defined BUILD_DONE if exist "%ROOT%\generate_buylist.py" (
  call :RUN "%PYTHON_EXE%" "%ROOT%\generate_buylist.py"
  set "BUILD_DONE=1"
)
if not defined BUILD_DONE if exist "%ROOT%\gen_buylist.py" (
  call :RUN "%PYTHON_EXE%" "%ROOT%\gen_buylist.py"
  set "BUILD_DONE=1"
)
if not defined BUILD_DONE if exist "%SCRIPTS%\generate_buylist.py" (
  call :RUN "%PYTHON_EXE%" "%SCRIPTS%\generate_buylist.py"
  set "BUILD_DONE=1"
)
if not defined BUILD_DONE if exist "%SCRIPTS%\gen_buylist.py" (
  call :RUN "%PYTHON_EXE%" "%SCRIPTS%\gen_buylist.py"
  set "BUILD_DONE=1"
)
if not defined BUILD_DONE call :DIE "No build script found or build did not run."

call :LOG "[4/9] Normalize build output"
if exist "%SCRIPTS_DOCS_DIR%\default\index.html" (
  call :LOG "[INFO] scripts\docs output found. Copy to root docs."
  robocopy "%SCRIPTS_DOCS_DIR%" "%DOCS_DIR%" /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS >> "%LOG_FILE%" 2>&1
  set "ROBO_RC=!ERRORLEVEL!"
  if !ROBO_RC! GEQ 8 call :DIE "robocopy scripts\docs to docs failed RC=!ROBO_RC!"
) else (
  call :LOG "[INFO] scripts\docs output not found. Use root docs."
)

call :LOG "[5/9] Verify outputs and detect data mode"
call :RESOLVE_INDEX_HTML
call :DETECT_DATA_MODE

call :LOG "[6/9] Git commit and push best effort"
cd /d "%ROOT%" || call :DIE "cd failed: %ROOT%"
git add docs >> "%LOG_FILE%" 2>&1
git add "%~nx0" >> "%LOG_FILE%" 2>&1
git diff --cached --quiet
if errorlevel 1 (
  git commit -m "update pokemon buylist" >> "%LOG_FILE%" 2>&1
  if errorlevel 1 call :LOG "[WARN] git commit failed. Continue."
  git pull --rebase --autostash >> "%LOG_FILE%" 2>&1
  if errorlevel 1 call :LOG "[WARN] git pull after commit failed. Continue."
  git push >> "%LOG_FILE%" 2>&1
  if errorlevel 1 call :LOG "[WARN] git push failed. Continue."
) else (
  call :LOG "[INFO] No git changes."
)

call :LOG "[7/9] Safe S3 upload"
call :DEPLOY_SAFE

call :LOG "[8/9] Sync latest Pokemon files to EC2"
call :SYNC_EC2

echo.
echo [OK] Done: %PUBLIC_URL%
echo [LOG] %LOG_FILE%
pause
exit /b 0


REM ============================================================
REM Functions
REM ============================================================

:RESOLVE_XLSM
set "XLSM="
for %%X in (
  "%ROOT%\buylist.xlsm"
  "%ROOT%\data\buylist.xlsm"
) do (
  if not defined XLSM (
    if exist "%%~fX" set "XLSM=%%~fX"
  )
)
if defined XLSM (
  call :LOG "[INFO] XLSM=%XLSM%"
) else (
  call :LOG "[WARN] XLSM not found from candidates. Continue if scripts do not require it."
)
exit /b 0


:RESOLVE_INDEX_HTML
set "INDEX_HTML="
for %%I in (
  "%DOCS_DIR%\default\index.html"
  "%DOCS_DIR%\default\default\index.html"
  "%SCRIPTS_DOCS_DIR%\default\index.html"
  "%SCRIPTS_DOCS_DIR%\default\default\index.html"
) do (
  if not defined INDEX_HTML (
    if exist "%%~fI" set "INDEX_HTML=%%~fI"
  )
)
if not defined INDEX_HTML call :DIE "index.html not found in known output locations"
call :LOG "[INFO] INDEX_HTML=%INDEX_HTML%"
exit /b 0


:DETECT_DATA_MODE
set "BUYLIST_JSON="
set "NEEDS_JSON=0"

findstr /i "__BUYLIST_API__ buylist.json" "%INDEX_HTML%" >nul 2>&1
if not errorlevel 1 set "NEEDS_JSON=1"

for %%J in (
  "%DOCS_DIR%\buylist.json"
  "%DOCS_DIR%\default\buylist.json"
  "%DOCS_DIR%\default\default\buylist.json"
  "%ROOT%\buylist.json"
  "%SCRIPTS_DOCS_DIR%\buylist.json"
  "%SCRIPTS_DOCS_DIR%\default\buylist.json"
  "%SCRIPTS_DOCS_DIR%\default\default\buylist.json"
) do (
  if not defined BUYLIST_JSON (
    if exist "%%~fJ" set "BUYLIST_JSON=%%~fJ"
  )
)

if defined BUYLIST_JSON (
  call :LOG "[INFO] External JSON mode. BUYLIST_JSON=%BUYLIST_JSON%"
  call :FIX_INDEX_API
  exit /b 0
)

if "%NEEDS_JSON%"=="1" (
  call :DIE "index.html requires buylist.json, but buylist.json was not found."
)

call :LOG "[INFO] Embedded HTML mode. buylist.json not required."
exit /b 0


:FIX_INDEX_API
call :LOG "[INFO] Fix index.html JSON path to ../buylist.json"
"%PYTHON_EXE%" -c "from pathlib import Path; import re, os; p=Path(os.environ['INDEX_HTML']); s=p.read_text(encoding='utf-8'); s=re.sub(r'window\.__BUYLIST_API__\s*=\s*[\x22\x27][^\x22\x27]+[\x22\x27];','window.__BUYLIST_API__=\x22../buylist.json\x22;',s); p.write_text(s,encoding='utf-8')" >> "%LOG_FILE%" 2>&1
if errorlevel 1 call :DIE "Failed to fix JSON path in index.html"
exit /b 0


:DEPLOY_SAFE
aws sts get-caller-identity >> "%LOG_FILE%" 2>&1
if errorlevel 1 call :DIE "AWS credential invalid. Run aws configure."

REM Upload only exact public files. No S3 root sync. No --delete.
aws s3 cp "%INDEX_HTML%" "s3://%S3_BUCKET%/%S3_PREFIX%/default/index.html" --cache-control "no-cache, no-store, must-revalidate" --content-type "text/html; charset=utf-8" >> "%LOG_FILE%" 2>&1
if errorlevel 1 call :DIE "S3 upload failed: default/index.html"

if defined BUYLIST_JSON (
  aws s3 cp "%BUYLIST_JSON%" "s3://%S3_BUCKET%/%S3_PREFIX%/buylist.json" --cache-control "no-cache, no-store, must-revalidate" --content-type "application/json; charset=utf-8" >> "%LOG_FILE%" 2>&1
  if errorlevel 1 call :DIE "S3 upload failed: buylist.json"
) else (
  call :LOG "[INFO] No buylist.json. Skip JSON upload."
)

if exist "%DOCS_DIR%\price_asc\index.html" (
  aws s3 cp "%DOCS_DIR%\price_asc\index.html" "s3://%S3_BUCKET%/%S3_PREFIX%/price_asc/index.html" --cache-control "no-cache, no-store, must-revalidate" --content-type "text/html; charset=utf-8" >> "%LOG_FILE%" 2>&1
  if errorlevel 1 call :DIE "S3 upload failed: price_asc/index.html"
)

if exist "%DOCS_DIR%\price_desc\index.html" (
  aws s3 cp "%DOCS_DIR%\price_desc\index.html" "s3://%S3_BUCKET%/%S3_PREFIX%/price_desc/index.html" --cache-control "no-cache, no-store, must-revalidate" --content-type "text/html; charset=utf-8" >> "%LOG_FILE%" 2>&1
  if errorlevel 1 call :DIE "S3 upload failed: price_desc/index.html"
)

REM Safe asset upload: limited to this category prefix and no --delete.
if exist "%DOCS_DIR%\assets" (
  aws s3 sync "%DOCS_DIR%\assets" "s3://%S3_BUCKET%/%S3_PREFIX%/assets/" --size-only --cache-control "public,max-age=31536000,immutable" --only-show-errors >> "%LOG_FILE%" 2>&1
  if errorlevel 1 call :DIE "S3 upload failed: assets"
)

aws cloudfront create-invalidation --distribution-id "%CF_DIST_ID%" --paths "/%S3_PREFIX%/default/*" "/%S3_PREFIX%/buylist.json" "/%S3_PREFIX%/price_asc/*" "/%S3_PREFIX%/price_desc/*" "/%S3_PREFIX%/assets/*" >> "%LOG_FILE%" 2>&1
if errorlevel 1 call :DIE "CloudFront invalidation failed"

exit /b 0


:SYNC_EC2
if not exist "%EC2_KEY%" (
  call :LOG "[WARN] EC2 key not found. Sync skipped: %EC2_KEY%"
  exit /b 0
)

ssh -i "%EC2_KEY%" %EC2_HOST% "mkdir -p %EC2_DIR%"
if errorlevel 1 call :DIE "EC2 directory creation failed: %EC2_DIR%"

REM Required update files
for %%F in (
  "buylist.xlsm"
  "scrape_torecabirth_pk_purchase.py"
  "update_buy_price_from_cardrush.py"
  "scrape_toreca_lounge_box_and_merge.py"
  "scrape_toreca_lounge_psa10.py"
  "export_sheet1_to_csv.py"
) do (
  if not exist "%ROOT%\%%~F" call :DIE "Required EC2 sync file missing: %%~F"
  scp -i "%EC2_KEY%" "%ROOT%\%%~F" %EC2_HOST%:%EC2_DIR%/
  if errorlevel 1 call :DIE "EC2 sync failed: %%~F"
)

REM Build scripts: send whichever exist
if exist "%ROOT%\generate_buylist.py" (
  scp -i "%EC2_KEY%" "%ROOT%\generate_buylist.py" %EC2_HOST%:%EC2_DIR%/
  if errorlevel 1 call :DIE "EC2 sync failed: generate_buylist.py"
)
if exist "%ROOT%\gen_buylist.py" (
  scp -i "%EC2_KEY%" "%ROOT%\gen_buylist.py" %EC2_HOST%:%EC2_DIR%/
  if errorlevel 1 call :DIE "EC2 sync failed: gen_buylist.py"
)

REM EC2 automation files are synced when placed in the repository root
if exist "%ROOT%\myca_auto_upload_pokemon_ec2.py" (
  scp -i "%EC2_KEY%" "%ROOT%\myca_auto_upload_pokemon_ec2.py" %EC2_HOST%:%EC2_DIR%/
  if errorlevel 1 call :DIE "EC2 sync failed: myca_auto_upload_pokemon_ec2.py"
)
if exist "%ROOT%\run_auto_update_pokemon.sh" (
  scp -i "%EC2_KEY%" "%ROOT%\run_auto_update_pokemon.sh" %EC2_HOST%:%EC2_DIR%/
  if errorlevel 1 call :DIE "EC2 sync failed: run_auto_update_pokemon.sh"
  ssh -i "%EC2_KEY%" %EC2_HOST% "chmod +x %EC2_DIR%/run_auto_update_pokemon.sh"
)
if exist "%ROOT%\pokemon-auto-update.service" (
  scp -i "%EC2_KEY%" "%ROOT%\pokemon-auto-update.service" %EC2_HOST%:%EC2_DIR%/
  if errorlevel 1 call :DIE "EC2 sync failed: pokemon-auto-update.service"
)
if exist "%ROOT%\pokemon-auto-update.timer" (
  scp -i "%EC2_KEY%" "%ROOT%\pokemon-auto-update.timer" %EC2_HOST%:%EC2_DIR%/
  if errorlevel 1 call :DIE "EC2 sync failed: pokemon-auto-update.timer"
)

REM Optional root assets used by some builders
for %%F in (instagram.png LINE.png logo.png tiktok.png X.png) do (
  if exist "%ROOT%\%%~F" (
    scp -i "%EC2_KEY%" "%ROOT%\%%~F" %EC2_HOST%:%EC2_DIR%/
    if errorlevel 1 call :DIE "EC2 sync failed: %%~F"
  )
)

call :LOG "[OK] EC2 sync completed: %EC2_DIR%"
exit /b 0


:SAFE_GIT_PULL
git rev-parse --is-inside-work-tree >> "%LOG_FILE%" 2>&1
if errorlevel 1 exit /b 0

git diff --quiet
set "D1=%ERRORLEVEL%"
git diff --cached --quiet
set "D2=%ERRORLEVEL%"

if not "%D1%%D2%"=="00" (
  call :LOG "[WARN] Working tree has local changes. Skip git pull."
  exit /b 0
)

git pull --rebase --autostash >> "%LOG_FILE%" 2>&1
if errorlevel 1 call :LOG "[WARN] git pull failed. Continue."

exit /b 0


:CHECK_TOOL
where %~1 >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Tool not found: %~1
  echo [ERROR] Tool not found: %~1>> "%LOG_FILE%"
  exit /b 1
)
exit /b 0


:RUN
echo [RUN] %*>> "%LOG_FILE%"
%* >> "%LOG_FILE%" 2>&1
if errorlevel 1 call :DIE "Command failed: %*"
exit /b 0


:LOG
echo %~1
echo %~1>> "%LOG_FILE%"
exit /b 0


:DIE
echo.
echo [ERROR] %~1
echo [ERROR] %~1>> "%LOG_FILE%"
echo [LOG] %LOG_FILE%
start "" notepad "%LOG_FILE%"
pause
exit /b 1


:END_FAIL
echo.
echo [ERROR] Setup failed.
echo [LOG] %LOG_FILE%
pause
exit /b 1
