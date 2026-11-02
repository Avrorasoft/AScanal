@echo off
title Sistema de Subida - CANAL 9 tva
color 0A

:: Configuración de Credenciales - Avrora Soft
set IA_ACCESS_KEY=X8X9EN1c2EX2kEzq
set IA_SECRET_KEY=8g1jFLmXyex3DXAq

echo ====================================================
echo   AVRORA SOFT - VIBOLA LLC: RESPALDO CANAL 9 tva
echo ====================================================
echo.

:: 1. Verificando si existe el archivo a subir
:: Cambia "video_noticia.mp4" por el nombre real de tu archivo
set ARCHIVO=video_noticia.mp4
set ID_ITEM=tva-riberalta-%date:~6,4%%date:~3,2%%date:~0,2%

if not exist %ARCHIVO% (
    echo [ERROR] No se encuentra el archivo: %ARCHIVO%
    pause
    exit
)

:: 2. Ejecutando la subida usando las llaves inyectadas
echo [INFO] Iniciando subida del material de prensa...
ia upload %ID_ITEM% %ARCHIVO% --metadata="title:Noticias Riberalta - CANAL 9 tva" --metadata="mediatype:movies" --access-key=%IA_ACCESS_KEY% --secret-key=%IA_SECRET_KEY%

if %errorlevel% equ 0 (
    echo.
    echo ====================================================
    echo [EXITO] Material subido a: https://archive.org/details/%ID_ITEM%
    echo ====================================================
) else (
    echo.
    echo [ERROR] La subida fallo. Verifica tu conexion o la cuenta.
)

pause