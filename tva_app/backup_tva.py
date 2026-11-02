import os
import shutil
from datetime import datetime

def crear_respaldo_integral():
    # Lista de archivos críticos de la arquitectura actual
    archivos_objetivo = [
        "lib/main.dart",
        "pubspec.yaml",
        "assets/config_tva.json"
    ]
    
    carpeta_destino = "respaldos_tva"
    
    # 1. Crear la bóveda principal si no existe
    if not os.path.exists(carpeta_destino):
        os.makedirs(carpeta_destino)
        
    # 2. Generar subcarpeta con sello de tiempo para esta etapa específica
    fecha_hora = datetime.now().strftime("%Y%m%d_%H%M%S")
    carpeta_etapa = os.path.join(carpeta_destino, f"etapa_{fecha_hora}")
    os.makedirs(carpeta_etapa)
    
    print("==================================================")
    print(" AVRORA SOFT - VIBOLA LLC | SISTEMA DE SEGURIDAD")
    print("==================================================")
    
    # 3. Ejecutar el clonado de seguridad
    for ruta_origen in archivos_objetivo:
        if os.path.exists(ruta_origen):
            nombre_archivo = os.path.basename(ruta_origen)
            ruta_destino = os.path.join(carpeta_etapa, nombre_archivo)
            shutil.copy2(ruta_origen, ruta_destino)
            print(f" -> Blindado: {nombre_archivo}")
        else:
            print(f" -> ADVERTENCIA: No se encontró {ruta_origen}")
            
    print("==================================================")
    print(f" Éxito: Etapa de geolocalización resguardada en:")
    print(f" {carpeta_etapa}")
    print("==================================================")

if __name__ == "__main__":
    crear_respaldo_integral()