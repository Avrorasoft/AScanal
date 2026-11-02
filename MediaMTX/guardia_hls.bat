@echo off
title TRANSMISOR CANAL 9 - GUARDIA ACTIVA

:inicio
echo Iniciando transmision HLS de Canal 9...
echo ===================================================

:: Pega justo debajo de esta linea TU comando original completo:
PEGA_AQUÍ_TU_LINEA_FFMPEG_ORIGINAL_QUE_FUNCIONABA

echo ===================================================
echo [ALERTA] LA TRANSMISION SE CAYO. 
echo REINICIANDO AUTOMATICAMENTE EN 2 SEGUNDOS...
timeout /t 2 >nul
goto inicio