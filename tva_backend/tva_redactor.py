import os
import json
import subprocess
import requests
import time
from datetime import datetime
import re
import boto3
from botocore.client import Config
import firebase_admin
from firebase_admin import credentials, messaging

# ==========================================================
# CONFIGURACIÓN CORPORATIVA - AVRORA SOFT / VIBOLA LLC
# ==========================================================

PATH_ENTRADA = r'C:\tva_backend\entrada_cronicas'
PATH_SALIDA_IMG = r'C:\tva_backend\miniaturas'
PATH_JSON_LOCAL = r'C:\tva_backend\noticias.json'
URL_R2_BASE = "https://vod.canal9.top"

R2_ACCESS_KEY = '21a17285638771b86fd7401d8e43d75b'
R2_SECRET_KEY = '82da22bcef3583cb83b6ddb4087d25f0bc98e720c745de477ca7abeb0374f20d'
R2_ENDPOINT = 'https://da292b98201102181e5228ea157e9980.r2.cloudflarestorage.com'
R2_BUCKET_NAME = 'vod-canal9'

s3 = boto3.client('s3',
    endpoint_url=R2_ENDPOINT,
    aws_access_key_id=R2_ACCESS_KEY,
    aws_secret_access_key=R2_SECRET_KEY,
    config=Config(signature_version='s3v4'),
    region_name='auto'
)

# INICIALIZACIÓN DEL MOTOR PUSH DE FIREBASE
try:
    if not firebase_admin._apps:
        cred = credentials.Certificate(r'C:\tva_backend\firebase_admin.json')
        firebase_admin.initialize_app(cred)
except Exception as e:
    print(f"[ERROR FIREBASE] No se pudo inicializar FCM: {e}")

def disparar_actualizacion_remota():
    """Envía un misil de actualización a todos los teléfonos con la app instalada"""
    try:
        mensaje = messaging.Message(
            data={'accion': 'forzar_actualizacion'},
            topic='tva_noticias'
        )
        respuesta = messaging.send(mensaje)
        print(f"[FCM] Orden de actualización PUSH disparada con éxito: {respuesta}")
    except Exception as e:
        print(f"[ERROR FCM] Falló el disparo a los teléfonos: {e}")

def limpiar_nombre(nombre):
    nombre = nombre.lower().replace(" ", "_")
    return re.sub(r'[^a-z0-9_]', '', nombre)

def subir_a_r2(path_local, nombre_remoto, content_type):
    print(f"[NUBE] Subiendo {nombre_remoto}...")
    try:
        s3.upload_file(
            path_local, 
            R2_BUCKET_NAME, 
            nombre_remoto, 
            ExtraArgs={
                'ContentType': content_type,
                'CacheControl': 'no-cache, no-store, must-revalidate'
            }
        )
        return True
    except Exception as e:
        print(f"[ERROR NUBE] {e}")
        return False

def generar_noticia_ia(nombre_archivo):
    print(f"[IA] Redactando nota para: {nombre_archivo}")
    tema = nombre_archivo.replace("_", " ")
    prompt = f"Escribe una noticia periodística formal para Canal 9 TVA Riberalta sobre: {tema}. Respuesta en JSON con campos exactos: titulo, descripcion y categoria."
    try:
        response = requests.post('http://localhost:11434/api/generate',
                                 json={"model": "llama3.2:3b", "prompt": prompt, "stream": False, "format": "json"})
        datos = json.loads(response.json()['response'])
        return {
            "titulo": datos.get('titulo', tema.capitalize()),
            "descripcion": datos.get('descripcion', 'Información en proceso desde la redacción de Canal 9.'),
            "categoria": datos.get('categoria', 'INFO')
        }
    except Exception as e:
        print(f"[ERROR IA] Falla en generación: {e}")
        return {"titulo": tema.capitalize(), "descripcion": "Nota en proceso.", "categoria": "SOCIAL"}

def extraer_miniatura(video_path, img_name):
    output_path = os.path.join(PATH_SALIDA_IMG, img_name)
    subprocess.run(f'ffmpeg -y -i "{video_path}" -ss 00:00:01 -vframes 1 "{output_path}"', shell=True, capture_output=True)
    subir_a_r2(output_path, f"miniaturas/{img_name}", "image/jpeg")
    return f"{URL_R2_BASE}/miniaturas/{img_name}"

def actualizar_feed():
    print(f"\n[SISTEMA] --- INICIO DE CICLO {datetime.now()} ---")
    
    if not os.path.exists(PATH_JSON_LOCAL):
        feed = {"version": 1, "feed_noticias": []}
    else:
        with open(PATH_JSON_LOCAL, 'r', encoding='utf-8') as f:
            feed = json.load(f)

    extensiones_video = ('.mp4', '.mov', '.mkv')
    extensiones_img = ('.jpg', '.jpeg', '.png')
    
    archivos = [f for f in os.listdir(PATH_ENTRADA) if f.lower().endswith(extensiones_video + extensiones_img)]
    
    if not archivos:
        print("[SISTEMA] No hay archivos nuevos.")
        return

    feed['version'] = feed.get('version', 0) + 1
    archivos_procesados = False

    for archivo in archivos:
        path_original = os.path.join(PATH_ENTRADA, archivo)
        nombre_limpio = limpiar_nombre(os.path.splitext(archivo)[0])
        ext_original = os.path.splitext(archivo)[1].lower()
        nuevo_nombre = f"{nombre_limpio}{ext_original}"
        
        datos_ia = generar_noticia_ia(nombre_limpio)
        
        es_video = ext_original in extensiones_video
        
        if es_video:
            url_img = extraer_miniatura(path_original, f"{nombre_limpio}.jpg")
            if subir_a_r2(path_original, nuevo_nombre, "video/mp4"):
                nueva_entrada = {
                    "id": datetime.now().strftime("%Y%m%d%H%M%S"),
                    "titulo": datos_ia.get('titulo', 'Sin título'),
                    "descripcion": datos_ia.get('descripcion', 'Información en desarrollo.'),
                    "imagen": url_img,
                    "videoUrl": f"{URL_R2_BASE}/{nuevo_nombre}",
                    "categoria": datos_ia.get('categoria', 'SOCIAL'),
                    "fecha": datetime.now().strftime("%d %b %Y")
                }
                feed['feed_noticias'].insert(0, nueva_entrada)
                os.remove(path_original)
                archivos_procesados = True
                print(f"[OK] Video publicado exitosamente.")
        else:
            content_type = "image/png" if ext_original == ".png" else "image/jpeg"
            if subir_a_r2(path_original, f"miniaturas/{nuevo_nombre}", content_type):
                url_img_directa = f"{URL_R2_BASE}/miniaturas/{nuevo_nombre}"
                nueva_entrada = {
                    "id": datetime.now().strftime("%Y%m%d%H%M%S"),
                    "titulo": datos_ia.get('titulo', 'Sin título'),
                    "descripcion": datos_ia.get('descripcion', 'Información en desarrollo.'),
                    "imagen": url_img_directa,
                    "videoUrl": None,
                    "categoria": datos_ia.get('categoria', 'SOCIAL'),
                    "fecha": datetime.now().strftime("%d %b %Y")
                }
                feed['feed_noticias'].insert(0, nueva_entrada)
                os.remove(path_original)
                archivos_procesados = True
                print(f"[OK] Imagen publicada exitosamente.")

    if archivos_procesados:
        with open(PATH_JSON_LOCAL, 'w', encoding='utf-8') as f:
            json.dump(feed, f, indent=4, ensure_ascii=False)
        
        subir_a_r2(PATH_JSON_LOCAL, "noticias.json", "application/json")
        print(f"[SISTEMA] Versión {feed['version']} publicada en R2.")
        disparar_actualizacion_remota()

if __name__ == "__main__":
    actualizar_feed()