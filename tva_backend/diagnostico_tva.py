import os
import json
import requests
import firebase_admin
from firebase_admin import credentials, db

PATH_JSON_LOCAL = r'C:\tva_backend\noticias.json'
URL_R2_JSON = 'https://vod.canal9.top/noticias.json'
FIREBASE_DB_URL = 'https://canal-9-tva-fe8dc-default-rtdb.firebaseio.com/'
PATH_CREDENCIALES_FIREBASE = r'C:\tva_backend\firebase_admin.json'

print("==================================================")
print("    DIAGNÓSTICO DE SINCRONIZACIÓN - CANAL 9 TVA")
print("==================================================")

# 1. Verificar archivo local
print("\n[1] Verificando archivo local (noticias.json)...")
if os.path.exists(PATH_JSON_LOCAL):
    try:
        with open(PATH_JSON_LOCAL, 'r', encoding='utf-8') as f:
            data_local = json.load(f)
            noticias_locales = data_local.get('feed_noticias', [])
            print(f"   [OK] Archivo local encontrado. Total de noticias locales: {len(noticias_locales)}")
            if len(noticias_locales) > 0:
                print(f"   [INFO] Última noticia local: {noticias_locales[0].get('titulo')}")
    except Exception as e:
        print(f"   [ERROR] El archivo local está corrupto o mal formado: {e}")
else:
    print("   [ERROR CRÍTICO] El archivo noticias.json no existe en C:\\tva_backend")

# 2. Verificar Cloudflare R2 (Internet)
print("\n[2] Verificando nube pública (Cloudflare R2)...")
try:
    response = requests.get(URL_R2_JSON, timeout=10)
    if response.status_code == 200:
        data_nube = response.json()
        noticias_nube = data_nube.get('feed_noticias', [])
        print(f"   [OK] Nube accesible. Total de noticias en la nube: {len(noticias_nube)}")
        if len(noticias_nube) > 0:
            print(f"   [INFO] Última noticia en la nube: {noticias_nube[0].get('titulo')}")
    else:
        print(f"   [ERROR] La nube respondió con código HTTP: {response.status_code}")
except Exception as e:
    print(f"   [ERROR] No se pudo conectar a la URL pública de R2: {e}")

# 3. Verificar Firebase Realtime Database
print("\n[3] Verificando base de datos en tiempo real (Firebase)...")
try:
    if not firebase_admin._apps:
        cred = credentials.Certificate(PATH_CREDENCIALES_FIREBASE)
        firebase_admin.initialize_app(cred, {'databaseURL': FIREBASE_DB_URL})
    
    ref_noticias = db.reference('noticias').get()
    if ref_noticias:
        print(f"   [OK] Firebase conectado. Nodos de noticias encontrados: {len(ref_noticias)}")
    else:
        print("   [ADVERTENCIA] Firebase está conectado pero el nodo 'noticias' está vacío.")
except Exception as e:
    print(f"   [ERROR] Falló la conexión a Firebase: {e}")

print("\n==================================================")
print("              FIN DEL DIAGNÓSTICO")
print("==================================================")