# -*- coding: utf-8 -*-
import os
import firebase_admin
from firebase_admin import credentials, db

CRED_PATH = r"C:\Canal9\tva_backend\firebase_admin.json"
FIREBASE_DB_URL = "https://canal-9-tva-fe8dc-default-rtdb.firebaseio.com"

if os.path.exists(CRED_PATH) and not firebase_admin._apps:
    cred = credentials.Certificate(CRED_PATH)
    firebase_admin.initialize_app(cred, {"databaseURL": FIREBASE_DB_URL})

print("--- [AVRORA SOFT] REVISIÓN DE CLAVES MULTIMEDIA EN FIREBASE ---")
ref = db.reference("noticias")
data = ref.get()

if isinstance(data, dict):
    for k, v in list(data.items())[:2]:
        print(f"\nNoticia ID: {k}")
        if isinstance(v, dict):
            keys_encontradas = list(v.keys())
            print(f"  Claves disponibles: {keys_encontradas}")
            for m in ["video", "videoUrl", "url", "media", "archivo"]:
                if m in v:
                    print(f"    -> [{m}]: {v[m]}")
else:
    print("[AVISO] No hay registros en Firebase.")
print("---------------------------------------------------------------")
