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
    ultimas = sorted(data.items(), key=lambda x: x[0], reverse=True)
    if ultimas:
        k, v = ultimas[0] # El más reciente
        url_valida = v.get("videoUrl") or v.get("video")
        if url_valida:
            db.reference(f"noticias/{k}").update({
                "video": url_valida,
                "videoUrl": url_valida
            })
            print(f"[CORREGIDO] Noticia {k} sincronizada: video y videoUrl apuntan a {url_valida}")
        else:
            print("[AVISO] El registro no tiene ninguna URL de video válida.")
