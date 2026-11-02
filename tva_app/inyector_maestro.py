import os
import subprocess
from datetime import datetime
import firebase_admin
from firebase_admin import credentials, db

# ==============================================================================
# AVRORA SOFT - VIBOLA LLC | INYECTOR MAESTRO VOD (ARCHIVE.ORG + FIREBASE)
# ==============================================================================

# Llaves maestras extraídas de la configuración nativa
IA_ACCESS_KEY = "X8X9EN1c2EX2kEzq"
IA_SECRET_KEY = "8g1jFLmXyex3DXAq"

# >>> ACCIÓN REQUERIDA: INYECTAR URL DE BASE DE DATOS <<<
FIREBASE_DB_URL = "https://TU-PROYECTO-FIREBASE.firebaseio.com/"

def limpiar_pantalla():
    os.system('cls' if os.name == 'nt' else 'clear')

def inyectar_material():
    limpiar_pantalla()
    print("====================================================")
    print("   CENTRO DE OPERACIONES - INYECTOR MAESTRO VOD")
    print("====================================================\n")

    # 1. Validación del Satélite de Firebase
    if not os.path.exists("serviceAccountKey.json"):
        print("[ERROR CRÍTICO] No se encontró la llave 'serviceAccountKey.json'.")
        print("Descárgala desde la consola de Firebase y colócala en esta carpeta.")
        return

    try:
        if not firebase_admin._apps:
            cred = credentials.Certificate("serviceAccountKey.json")
            firebase_admin.initialize_app(cred, {'databaseURL': FIREBASE_DB_URL})
    except Exception as e:
        print(f"[ERROR] Ruptura de conexión con Firebase: {e}")
        return

    # 2. Captura de Datos VOD
    ruta_archivo = input("-> Arrastra el archivo de video (.mp4) aquí y presiona ENTER:\n").strip().strip('"').strip("'")
    if not os.path.exists(ruta_archivo):
        print(f"\n[ERROR] El archivo no existe en la ruta: {ruta_archivo}")
        return

    titulo = input("\n-> Escribe el Titular de la Noticia:\n").strip()
    if not titulo:
        print("\n[ERROR] La inyección requiere un titular obligatorio.")
        return

    # 3. Transferencia Pesada a Archive.org
    nombre_archivo = os.path.basename(ruta_archivo)
    fecha_str = datetime.now().strftime("%Y%m%d")
    timestamp_actual = int(datetime.now().timestamp())
    id_item = f"tva-riberalta-{fecha_str}-{timestamp_actual}"

    print(f"\n[INFO] Desplegando ruteo hacia Archive.org bajo ID: {id_item}...")

    comando_ia = [
        "ia", "upload", id_item, ruta_archivo,
        "--metadata=title:Noticias Riberalta - CANAL 9 tva",
        "--metadata=mediatype:movies",
        f"--access-key={IA_ACCESS_KEY}",
        f"--secret-key={IA_SECRET_KEY}"
    ]

    proceso = subprocess.run(comando_ia, capture_output=True, text=True)

    if proceso.returncode != 0:
        print(f"\n[ERROR CRÍTICO] Fallo en el puente de subida:\n{proceso.stderr}")
        return

    print("\n[ÉXITO] Nodo de video alojado correctamente.")

    # 4. Construcción Estructural del Nodo JSON
    url_video = f"https://archive.org/download/{id_item}/{nombre_archivo}"
    id_firebase = str(timestamp_actual * 1000)
    fecha_iso = datetime.now().strftime("%Y-%m-%d")

    payload = {
        'id': id_firebase,
        'titulo': titulo,
        'fecha': fecha_iso,
        'videoUrl': url_video,
        'imagen': "", 
        'likes': 0,
        'dislikes': 0,
        'sad': 0,
        'happy': 0,
        'vistos': 0
    }

    # 5. Inyección Directa en Base de Datos
    print("[INFO] Sincronizando con Firebase Realtime Database...")
    try:
        ref = db.reference(f'noticias/{id_firebase}')
        ref.set(payload)
        print("====================================================")
        print(" [SISTEMA ESTABLE] Noticia inyectada en la App")
        print("====================================================")
        print(f" -> Titular: {titulo}")
        print(f" -> Enlace VOD: {url_video}")
    except Exception as e:
        print(f"\n[ERROR] El archivo de video subió, pero falló la inyección de la tarjeta: {e}")

if __name__ == "__main__":
    inyectar_material()
    input("\nPresiona ENTER para cerrar el inyector...")