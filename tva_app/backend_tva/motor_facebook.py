import os
import json
import time
import subprocess
import pickle
from datetime import datetime
import requests
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By

# =====================================================================
# AVRORA SOFT - VIBOLA LLC | MOTOR DE EXTRACCIÓN Y NAVEGACIÓN META
# Proyecto: CANAL 9 TVA
# =====================================================================

# Credenciales maestras de Archive.org
ARCHIVE_ACCESS_KEY = "X8X9EN1c2EX2kEzq"
ARCHIVE_SECRET_KEY = "8g1jFLmXyex3DXAq"

# Configuración de carpetas temporales
DIRECTORIO_TEMP = "temp_tva"

def inicializar_entorno():
    """Prepara el directorio temporal para las descargas."""
    if not os.path.exists(DIRECTORIO_TEMP):
        os.makedirs(DIRECTORIO_TEMP)
        print(f"[*] Directorio temporal '{DIRECTORIO_TEMP}' preparado.")

def descargar_video_facebook(url_post, id_noticia):
    """
    Usa yt-dlp mediante subprocess para forzar la descarga del MP4 desde Facebook.
    """
    print(f"[*] Iniciando extracción de video con yt-dlp...")
    ruta_salida = os.path.join(DIRECTORIO_TEMP, f"{id_noticia}.mp4")
    
    comando = [
        "yt-dlp",
        "--force-ipv4",
        "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]",
        "-o", ruta_salida,
        url_post
    ]
    
    try:
        resultado = subprocess.run(comando, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if os.path.exists(ruta_salida):
            print(f"[+] Video descargado con éxito: {ruta_salida}")
            return ruta_salida
        else:
            print(f"[-] Fallo en la descarga del video. Verifica la URL o tu conexión.")
            return None
    except Exception as e:
        print(f"[-] Error crítico en la ejecución de yt-dlp: {e}")
        return None

def analizar_formato_video_ffmpeg(ruta_video):
    """
    Analiza si el video es vertical (9:16) o apaisado (16:9) usando FFprobe directo.
    CUMPLIMIENTO ESTRICTO: Uso exclusivo de subprocess, prohibido moviepy.
    """
    print(f"[*] Analizando geometría del video con FFmpeg directo...")
    comando_ffprobe = [
        "ffprobe",
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height",
        "-of", "csv=s=x:p=0",
        ruta_video
    ]
    
    try:
        resultado = subprocess.run(comando_ffprobe, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        dimensiones = resultado.stdout.strip().split('x')
        
        if len(dimensiones) == 2:
            ancho = int(dimensiones[0])
            alto = int(dimensiones[1])
            print(f"[*] Dimensiones detectadas: {ancho}x{alto}")
            
            es_vertical = alto > ancho
            print(f"[+] Formato vertical: {es_vertical}")
            return es_vertical
        else:
            print("[-] No se pudieron leer las dimensiones con FFprobe. Asumiendo apaisado (False).")
            return False
    except Exception as e:
        print(f"[-] Error crítico ejecutando FFprobe: {e}")
        return False

def subir_a_archive_org(ruta_video, id_noticia, titulo_limpio):
    """
    Sube el archivo físico a Archive.org para obtener un enlace público y eterno.
    """
    print(f"[*] Transmitiendo a la bóveda de Archive.org...")
    identificador_item = f"tva-noticia-fb-{id_noticia}"
    nombre_archivo = f"{id_noticia}.mp4"
    url_subida = f"http://s3.us.archive.org/{identificador_item}/{nombre_archivo}"
    
    headers = {
        "Authorization": f"LOW {ARCHIVE_ACCESS_KEY}:{ARCHIVE_SECRET_KEY}",
        "x-archive-meta-collection": "opensource_media",
        "x-archive-meta-mediatype": "movies",
        "x-archive-meta-title": f"CANAL 9 TVA - Noticia {id_noticia}",
        "x-archive-meta-creator": "Avrora Soft - Vibola LLC"
    }

    try:
        with open(ruta_video, 'rb') as data:
            respuesta = requests.put(url_subida, headers=headers, data=data)
            
        if respuesta.status_code == 200:
            enlace_publico = f"https://archive.org/download/{identificador_item}/{nombre_archivo}"
            print(f"[+] Subida exitosa. Enlace permanente generado: {enlace_publico}")
            return enlace_publico
        else:
            print(f"[-] Error en Archive.org HTTP {respuesta.status_code}: {respuesta.text}")
            return None
    except Exception as e:
        print(f"[-] Falla de conexión con Archive.org: {e}")
        return None

def actualizar_json_tva(nueva_noticia):
    """Integra la nueva noticia en el JSON maestro de la aplicación."""
    archivo_json = "noticias_actualizadas.json"
    noticias = []
    
    if os.path.exists(archivo_json):
        with open(archivo_json, 'r', encoding='utf-8') as f:
            try:
                noticias = json.load(f)
            except json.JSONDecodeError:
                noticias = []
            
    noticias.insert(0, nueva_noticia)
    
    with open(archivo_json, 'w', encoding='utf-8') as f:
        json.dump(noticias, f, ensure_ascii=False, indent=4)
    print(f"[+] Archivo {archivo_json} actualizado correctamente.")

def procesar_post_facebook(url_post, categoria, texto_crudo):
    """Flujo de automatización para descargar, analizar, subir y empaquetar."""
    titulo = texto_crudo[:40] + "..." if len(texto_crudo) > 40 else texto_crudo
    if not titulo.strip():
        titulo = "Reporte Local Especial"

    print("\n" + "="*50)
    print(f" PROCESANDO POST: {titulo}")
    print("="*50)
    
    timestamp = str(int(time.time()))
    id_noticia = f"fb_{timestamp}"
    
    # 1. Descargar Video
    ruta_video = descargar_video_facebook(url_post, id_noticia)
    if not ruta_video:
        print("[-] Abortando proceso para esta noticia.")
        return
        
    # 2. Analizar Geometría (FFmpeg estricto)
    es_vertical = analizar_formato_video_ffmpeg(ruta_video)
    
    # 3. Subir a Bóveda
    url_permanente = subir_a_archive_org(ruta_video, id_noticia, titulo)
    
    if url_permanente:
        # 4. Construir objeto JSON para Flutter
        nueva_noticia = {
            "categoria": categoria,
            "titulo": titulo,
            "descripcion": texto_crudo,
            "fecha": datetime.now().strftime("%d/%m/%Y"),
            "imagen": url_permanente, 
            "esVertical": es_vertical
        }
        actualizar_json_tva(nueva_noticia)
        
    # 5. Limpieza de memoria y disco
    if os.path.exists(ruta_video):
        os.remove(ruta_video)
        print(f"[*] Archivo local temporal {ruta_video} eliminado.")

# --- MÓDULO DE RASTREO TÁCTICO CON INYECCIÓN DE SESIÓN (SELENIUM) ---

def iniciar_rastreador_fantasma():
    """Configura y levanta el navegador. MODO VISIBLE ACTIVADO PARA DEPURACIÓN."""
    print("\n[*] Inicializando motor de rastreo Selenium en modo VISIBLE...")
    opciones = Options()
    
    # LÍNEA COMENTADA PARA QUITAR LA VENDA Y VER EL NAVEGADOR
    # opciones.add_argument("--headless")
    
    opciones.add_argument("--disable-gpu")
    opciones.add_argument("--no-sandbox")
    opciones.add_argument("--disable-dev-shm-usage")
    opciones.add_argument("user-agent=Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1")
    
    driver = webdriver.Chrome(options=opciones)
    return driver

def inyectar_llave_sesion(driver):
    """Inyecta las cookies de sesión en el navegador."""
    print("[*] Accediendo a zona neutral de Facebook para inyección...")
    driver.get("https://mbasic.facebook.com")
    time.sleep(2)
    
    try:
        with open("cookies_fb.pkl", "rb") as archivo:
            cookies = pickle.load(archivo)
            for cookie in cookies:
                driver.add_cookie(cookie)
        print("[+] Llave maestra (Cookies) inyectada correctamente.")
    except FileNotFoundError:
        print("[-] ALERTA CRÍTICA: No se encontró 'cookies_fb.pkl'. Ejecuta generar_llave_fb.py primero.")

def raspar_pagina_mbasic(driver, url_objetivo):
    """
    Infiltra la versión mbasic y extrae texto y enlaces de video con radar ampliado.
    """
    print(f"[*] Desplegando en objetivo: {url_objetivo}")
    driver.get(url_objetivo)
    
    print("[*] Pausa táctica de 10 segundos para inspección visual de la pantalla...")
    time.sleep(10) 
    
    noticias_encontradas = []
    
    # RADAR AMPLIADO: Captura enlaces con video, watch, story o el texto Reproducir
    xpath_ampliado = "//a[contains(@href, 'video') or contains(@href, 'watch') or contains(@href, 'story') or contains(text(), 'Reproducir')]"
    enlaces_video = driver.find_elements(By.XPATH, xpath_ampliado)
    
    print(f"[*] El escáner detectó {len(enlaces_video)} posibles nodos multimedia.")
    
    for enlace in enlaces_video:
        url_video_encriptada = enlace.get_attribute("href")
        print(f"    -> Interceptado: {url_video_encriptada}") # Depuración visual en terminal
        
        try:
            # Subimos en la jerarquía HTML para buscar el texto de la noticia
            contenedor_padre = enlace.find_element(By.XPATH, "./../../..")
            texto_crudo = contenedor_padre.text
            lineas = texto_crudo.split('\n')
            texto_limpio = " ".join([l for l in lineas if "Me gusta" not in l and "Comentar" not in l and "Compartir" not in l and "Reproducir" not in l])
            
            if url_video_encriptada and url_video_encriptada not in [n['url'] for n in noticias_encontradas]:
                noticias_encontradas.append({
                    "url": url_video_encriptada,
                    "texto": texto_limpio.strip()
                })
        except Exception as e:
            # Si falla al capturar el texto, guardamos el enlace de todos modos
            if url_video_encriptada and url_video_encriptada not in [n['url'] for n in noticias_encontradas]:
                noticias_encontradas.append({
                    "url": url_video_encriptada,
                    "texto": "Reporte en video de Elay Diario Digital Riberalteño."
                })

    return noticias_encontradas

# =====================================================================
# EJECUCIÓN PRINCIPAL DEL SISTEMA
# =====================================================================
if __name__ == "__main__":
    inicializar_entorno()
    
    URL_OBJETIVO = "https://mbasic.facebook.com/elaydiariodigitalriberalteno"
    CATEGORIA_DEFECTO = "LOCAL"
    
    driver = None
    try:
        driver = iniciar_rastreador_fantasma()
        
        inyectar_llave_sesion(driver)
        
        noticias_extraidas = raspar_pagina_mbasic(driver, URL_OBJETIVO)
        
        if not noticias_extraidas:
            print("[-] No se pudieron extraer datos utilizables de los nodos multimedia.")
        else:
            print(f"[+] Se filtraron {len(noticias_extraidas)} enlaces únicos para descarga.")
            
        for noticia in noticias_extraidas[:3]:
            texto_post = noticia['texto'] if len(noticia['texto']) > 5 else "Reporte en video desde Elay Diario Digital Riberalteño."
            
            procesar_post_facebook(
                url_post=noticia['url'],
                categoria=CATEGORIA_DEFECTO,
                texto_crudo=texto_post
            )
            time.sleep(5) 
            
    except Exception as error_global:
        print(f"[-] Falla general en el motor de rastreo: {error_global}")
    finally:
        if driver:
            driver.quit()
            print("[*] Navegador cerrado. Operación concluida.")