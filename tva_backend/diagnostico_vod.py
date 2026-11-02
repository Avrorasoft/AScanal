# -*- coding: utf-8 -*-
import os

BASE_DIR = r"C:\Canal9\tva_backend"
VOD_FOLDER = os.path.join(BASE_DIR, "vod_local")

print("--- [AVRORA SOFT] DIAGNÓSTICO AUTOMÁTICO VOD ---")

# 1. Verificar carpeta vod_local
if os.path.exists(VOD_FOLDER):
    print(f"[OK] La carpeta de medios existe en: {VOD_FOLDER}")
    # Comprobar permisos de escritura
    test_file = os.path.join(VOD_FOLDER, "test_permisos.tmp")
    try:
        with open(test_file, "w") as f:
            f.write("test")
        os.remove(test_file)
        print("[OK] Permisos de escritura en 'vod_local': CORRECTOS.")
    except Exception as e:
        print(f"[ERROR] Sin permisos de escritura en la carpeta: {e}")
else:
    print(f"[ADVERTENCIA] La carpeta no existe. Creándola...")
    os.makedirs(VOD_FOLDER, exist_ok=True)
    print("[OK] Carpeta creada.")

# 2. Listar archivos multimedia actuales en disco
archivos = os.listdir(VOD_FOLDER)
print(f"[INFO] Archivos físicos encontrados en disco ({len(archivos)}):")
for arch in archivos:
    ruta_a = os.path.join(VOD_FOLDER, arch)
    tamanio_mb = os.path.getsize(ruta_a) / (1024 * 1024)
    print(f" -> {arch} ({tamanio_mb:.2f} MB)")

print("--------------------------------------------------")