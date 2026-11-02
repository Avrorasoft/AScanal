# -*- coding: utf-8 -*-
import os
import firebase_admin
from firebase_admin import credentials, db

CRED_PATH = r"C:\Canal9\tva_backend\firebase_admin.json"
FIREBASE_DB_URL = "https://canal-9-tva-fe8dc-default-rtdb.firebaseio.com"

if os.path.exists(CRED_PATH) and not firebase_admin._apps:
    cred = credentials.Certificate(CRED_PATH)
    firebase_admin.initialize_app(cred, {"databaseURL": FIREBASE_DB_URL})

print("--- [AVRORA SOFT] CORRECCIÓN MASIVA DE URLS EN FIREBASE ---")
ref = db.reference("noticias")
data = ref.get()

IP_LOCAL = "192.168.0.104"
PUERTO = 5000

actualizados = 0
if isinstance(data, dict):
    for k, v in data.items():
        if isinstance(v, dict):
            updates = {}
            # Revisar videoUrl
            v_url = v.get("videoUrl", "")
            if v_url and ("vod.canal9.top" in v_url or "localhost" in v_url or "192.168.1." in v_url):
                nombre_archivo = v_url.split("/")[-1]
                if nombre_archivo:
                    nueva_v = f"http://{IP_LOCAL}:{PUERTO}/vod_local/{nombre_archivo}"
                    updates["videoUrl"] = nueva_v
                    updates["video"] = nueva_v

            # Revisar imagen
            i_url = v.get("imagen", "") or v.get("imagenUrl", "")
            if i_url and ("vod.canal9.top" in i_url or "localhost" in i_url or "192.168.1." in i_url):
                nombre_img = i_url.split("/")[-1]
                if nombre_img:
                    nueva_i = f"http://{IP_LOCAL}:{PUERTO}/vod_local/{nombre_img}"
                    updates["imagen"] = nueva_i
                    updates["imagenUrl"] = nueva_i

            if updates:
                db.reference(f"noticias/{k}").update(updates)
                print(f"[CORREGIDO] Noticia {k}: URLs actualizadas a red local.")
                actualizados += 1

print(f"\n[ÉXITO] Se actualizaron {actualizados} registros en Firebase con rutas locales accesibles.")
print("----------------------------------------------------------")
