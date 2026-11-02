@echo off
:: Forzar la ruta a la carpeta donde está el archivo
cd /d "%~dp0"

echo =======================================================
echo    CANAL 9 TVA - DIAGNOSTICO DE ARRANQUE
echo =======================================================

:: Verificar archivos críticos
if not exist "mediamtx.exe" echo [ALERTA] No veo a mediamtx.exe en esta carpeta.
if not exist "cloudflared.exe" echo [ALERTA] No veo a cloudflared.exe en esta carpeta.
if not exist "ffmpeg.exe" echo [ALERTA] No veo a ffmpeg.exe en esta carpeta.

echo.
echo [%time%] Iniciando MediaMTX...
start "SERVIDOR" mediamtx.exe

echo [%time%] Iniciando Cloudflared...
start "TUNEL" powershell.exe -NoExit -Command "& {./cloudflared.exe tunnel --no-autoupdate run --token eyJhIjoiZGEyOTJiOTgyMDExMDIxODFlNTIyOGVhMTU3ZTk5ODAiLCJ0IjoiZDkyZjdlMDMtYTI3YS00ZDdiLWJhZTMtODQ3MWRhMzdiYmY4IiwicyI6Ik5qWTFOV1V6WlRBdFlUYzNPQzAwWlRKaUxXSTRabVl0WlRsalptSm1NbVEwTmpJNCJ9}"

timeout /t 5 >nul

echo [%time%] Lanzando Motor de Video...
:loop
:: Aqui esta la magia: -rtbufsize 512M y -thread_queue_size 512
ffmpeg -f dshow -rtbufsize 512M -thread_queue_size 512 -i video="NDI Webcam Video 1":audio="Webcam 1 (NDI Webcam Audio)" -vf "scale=1280:720,setdar=16/9,format=yuv420p" -r 30 -c:v libx264 -profile:v main -preset ultrafast -b:v 1500k -maxrate 1800k -bufsize 3600k -g 60 -keyint_min 60 -sc_threshold 0 -c:a aac -b:a 128k -f flv rtmp://127.0.0.1:1936/live/tv
flv rtmp://127.0.0.1:1936/live/tv

echo.
echo ===================================================
echo [%time%] [ALERTA] EL MOTOR FFMPEG SE DETUVO. 
echo REINICIANDO AUTOMATICAMENTE EN 3 SEGUNDOS...
echo ===================================================
timeout /t 3 >nul
goto loop