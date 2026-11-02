import os
import json
import time
import subprocess
import pickle
from datetime import datetime
import boto3
from botocore.client import Config

# =====================================================================
# AVRORA SOFT - VIBOLA LLC | LANZADOR BLINDADO V5 (MODO ESTABLE SD)
# Proyecto: CANAL 9 TVA - TELEVISIÓN AMAZÓNICA-RIBERALTA
# =====================================================================

R2_ACCESS_KEY = '21a17285638771b86fd7401d8e43d75b'
R2_SECRET_KEY = '82da22bcef3583cb83b6ddb4087d25f0bc98e720c745de477ca7abeb0374f20d'
R2_ENDPOINT = 'https://da292b98201102181e5228ea157e9980.r2.cloudflarestorage.com'
R2_BUCKET_NAME = 'vod-canal9'
URL_R2_BASE = 'https://vod.canal9.top'

DIRECTORIO_TEMP = "temp_tva"

YT_DLP = os.path.join(os.getcwd(), "yt-dlp.exe")
FFMPEG = os.path.join(os.getcwd(), "ffmpeg.exe")
FFPROBE = os.path.join(os.getcwd(), "ffprobe.exe")
COOKIES_PKL = os.path.join(os.getcwd(), "cookies_fb.pkl")
COOKIES_TXT = os.path.join(os.getcwd(), "cookies_temp.txt")

# Inicializar cliente S3 para Cloudflare R2
s3 = boto3.client('s3',
    endpoint_url=R2_ENDPOINT,
    aws_access_key_id=R2_ACCESS_KEY,
    aws_secret_access_key=R2_SECRET_KEY,
    config=Config(signature_version='s3v4'),
    region_name='auto'
)

def preparar_cookies():
    """Convierte el archivo PKL a formato Netscape que yt-dlp entiende."""
    if os.path.exists(COOKIES_PKL):
        try:
            with open(COOKIES_PKL, "rb") as f:
                cookies = pickle.load(f)
            with open(COOKIES_TXT, "w") as f:
                f.write("# Netscape HTTP Cookie File\n")
                for c in cookies:
                    domain = c.get('domain', '')
                    path = c.get('path', '/')
                    secure = "TRUE" if c.get('secure') else "FALSE"
                    expires = str(int(c.get('expiry', time.time() + 36000)))
                    name = c.get('name', '')
                    value = c.get('value', '')
                    f.write(f"{domain}\tTRUE\t{path}\t{secure}\t{expires}\t{name}\t{value}\n")
            return True
        except Exception as e:
            print(f"[!] Error convirtiendo llaves: {e}")
    return False

def procesar_video(url, cat, tit, desc):
    if not os.path.exists(DIRECTORIO_TEMP): os.makedirs(DIRECTORIO_TEMP)
    preparar_cookies()
    
    timestamp = str(int(time.time()))
    id_not = f"tva_{timestamp}"
    ruta = os.path.join(DIRECTORIO_TEMP, f"{id_not}.mp4")
    
    print(f"\n[*] Extrayendo noticia en MODO ESTABLE (SD): {tit}...")
    
    # COMANDO OPTIMIZADO PARA RIBERALTA: Prioriza SD para evitar Timeouts
    cmd_dl = [
        YT_DLP, 
        "--force-ipv4", 
        "--cookies", COOKIES_TXT,
        "--no-check-certificate",
        "-f", "worstvideo[ext=mp4]+bestaudio[ext=m4a]/worst[ext=mp4]",
        "-o", ruta, 
        url
    ]
    
    try:
        subprocess.run(cmd_dl, check=True)
        
        # =========================================================================
        # OPTIMIZACIÓN FASTSTART PARA CARGA INSTANTÁNEA EN LA APP
        # =========================================================================
        print("[*] Optimizando video para reproducción instantánea en la App (Faststart)...")
        ruta_optimizada = os.path.join(DIRECTORIO_TEMP, f"{id_not}_opt.mp4")
        
        cmd_faststart = [
            FFMPEG, "-y", "-i", ruta, 
            "-c", "copy", 
            "-movflags", "faststart", 
            ruta_optimizada
        ]
        
        subprocess.run(cmd_faststart, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
        
        if os.path.exists(ruta_optimizada):
            os.remove(ruta)
            os.rename(ruta_optimizada, ruta)
        # =========================================================================
        
        print("[*] Midiendo dimensiones con FFprobe...")
        probe = subprocess.run([FFPROBE, "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=s=x:p=0", ruta], stdout=subprocess.PIPE, text=True)
        w, h = map(int, probe.stdout.strip().split('x'))
        es_v = h > w
        
        print("[*] Transmitiendo a la nube (Cloudflare R2)...")
        nombre_remoto = f"{id_not}.mp4"
        
        s3.upload_file(
            ruta, 
            R2_BUCKET_NAME, 
            nombre_remoto, 
            ExtraArgs={
                'ContentType': 'video/mp4',
                'CacheControl': 'no-cache, no-store, must-revalidate'
            }
        )
        
        link_final = f"{URL_R2_BASE}/{nombre_remoto}"
        
        # Registro en el JSON maestro para la aplicación
        noticia = {
            "categoria": cat, 
            "titulo": tit, 
            "descripcion": desc, 
            "fecha": datetime.now().strftime("%d/%m/%Y"), 
            "imagen": link_final, 
            "esVertical": es_v
        }
        
        db = "noticias_actualizadas.json"
        lista = []
        if os.path.exists(db):
            with open(db, 'r', encoding='utf-8') as f:
                try: lista = json.load(f)
                except: lista = []
        
        lista.insert(0, noticia)
        with open(db, 'w', encoding='utf-8') as f:
            json.dump(lista, f, ensure_ascii=False, indent=4)
        
        # Limpieza de archivos temporales
        if os.path.exists(ruta): os.remove(ruta)
        if os.path.exists(COOKIES_TXT): os.remove(COOKIES_TXT)
        print(f"\n[+] ¡ÉXITO! Noticia publicada en CANAL 9 TVA y alojada en R2.")
        
    except Exception as e:
        print(f"[-] Error crítico en el motor: {e}")

if __name__ == "__main__":
    print("======================================================")
    print("  LANZADOR BLINDADO V5 (SD) - CANAL 9 TVA")
    print("  ESTADO: PRIORIDAD ESTABILIDAD RIBERALTA (R2 CLOUD)")
    print("======================================================")
    
    while True:
        link = input("\n[1] Pega el LINK (o 'salir'): ").strip()
        if link.lower() == 'salir': break
        
        titulo = input("[2] Título de la noticia: ").strip() or "Noticia de Riberalta"
        desc = input("[3] Descripción: ").strip() or "Reporte de Televisión Amazónica."
        cat = input("[4] Categoría (LOCAL/NACIONAL): ").strip().upper() or "LOCAL"
        
        procesar_video(link, cat, titulo, desc)
        print("\n--- ¿Siguiente reporte, Ramiro? ---")