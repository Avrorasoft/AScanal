# -*- coding: utf-8 -*-
import os
import firebase_admin
from firebase_admin import credentials, db

CRED_PATH = r"C:\Canal9\tva_backend\firebase_admin.json"
FIREBASE_DB_URL = "https://canal-9-tva-fe8dc-default-rtdb.firebaseio.com"

if os.path.exists(CRED_PATH) and not firebase_admin._apps:
    cred = credentials.Certificate(CRED_PATH)
    firebase_admin.initialize_app(cred, {"databaseURL": FIREBASE_DB_URL})

print("--- [AVRORA SOFT] INSPECCIÓN DE LLAVES EN FIREBASE ---")
ref = db.reference("noticias")
data = ref.get()

if isinstance(data, dict):
    for k, v in list(data.items())[:3]: # Muestra los primeros 3 registros
        print(f"\n[ID/Key]: {k}")
        if isinstance(v, dict):
            for sub_k, sub_v in v.items():
                if any(x in sub_k.lower() for x in ["video", "url", "img", "audio", "cuerpo", "titulo"]):
                    print(f"   -> {sub_k}: {sub_v}")
else:
    print("[AVISO] No se encontraron noticias en Firebase o la estructura está vacía.")

print("-----------------------------------------------------")
