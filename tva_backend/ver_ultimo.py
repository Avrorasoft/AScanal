# -*- coding: utf-8 -*-
import os
import firebase_admin
from firebase_admin import credentials, db

CRED_PATH = r"C:\Canal9\tva_backend\firebase_admin.json"
FIREBASE_DB_URL = "https://canal-9-tva-fe8dc-default-rtdb.firebaseio.com"

if os.path.exists(CRED_PATH) and not firebase_admin._apps:
    cred = credentials.Certificate(CRED_PATH)
    firebase_admin.initialize_app(cred, {"databaseURL": FIREBASE_DB_URL})

ref = db.reference("noticias")
data = ref.get()

if isinstance(data, dict):
    # Ordenar por clave (timestamp/ID) para ver el más reciente
    ultimas = sorted(data.items(), key=lambda x: x[0], reverse=True)[:2]
    print("--- [AVRORA SOFT] ÚLTIMOS REGISTROS EN FIREBASE ---")
    for k, v in ultimas:
        print(f"\nID: {k}")
        print(f"  Título: {v.get('titulo')}")
        print(f"  video: {v.get('video')}")
        print(f"  videoUrl: {v.get('videoUrl')}")
print("---------------------------------------------------")
