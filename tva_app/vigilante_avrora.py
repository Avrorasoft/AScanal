import os, shutil, time

# --- CONFIGURACIÓN PARA RAMIRO ---
CARPETA_DESCARGAS = r"C:\Users\EDICION-GRANDE\Downloads" 

# Directorio raíz del proyecto (donde se ejecuta el script)
RAIZ_PROYECTO = os.getcwd()
CARPETA_ENTREGAS = os.path.join(RAIZ_PROYECTO, "Entregas_Gemini")

PREFIJO_PROYECTO = "tva_" 
EXTENSIONES_PERMITIDAS = ['.txt', '.dart', '.py', '.json', '.yaml']

def mover():
    if not os.path.exists(CARPETA_ENTREGAS):
        os.makedirs(CARPETA_ENTREGAS)
    
    for f in os.listdir(CARPETA_DESCARGAS):
        if f.startswith(PREFIJO_PROYECTO) and any(f.endswith(ex) for ex in EXTENSIONES_PERMITIDAS):
            
            if f.endswith('.crdownload') or f.endswith('.part'):
                continue
                
            ruta_origen = os.path.join(CARPETA_DESCARGAS, f)
            
            # --- LÓGICA DE ENRUTAMIENTO INTELIGENTE ---
            # 1. Si es el main.dart (quitando el prefijo tva_)
            if f == "tva_main.dart":
                ruta_destino = os.path.join(RAIZ_PROYECTO, "lib", "main.dart")
                msg = "🚀 main.dart actualizado en lib/"
            
            # 2. Si es el pubspec.yaml
            elif f == "tva_pubspec.yaml":
                ruta_destino = os.path.join(RAIZ_PROYECTO, "pubspec.yaml")
                msg = "⚙️ pubspec.yaml actualizado en la raíz"
            
            # 3. Todo lo demás va a Entregas_Gemini
            else:
                ruta_destino = os.path.join(CARPETA_ENTREGAS, f)
                msg = f"📂 Archivo movido a Entregas_Gemini: {f}"

            try:
                # Aseguramos que la carpeta lib exista si vamos a mover el main
                if "lib" in ruta_destino and not os.path.exists(os.path.dirname(ruta_destino)):
                    os.makedirs(os.path.dirname(ruta_destino))
                
                # Usamos replace o move. Para archivos existentes en lib, move fallaría si ya existe,
                # por eso intentamos eliminar el destino primero para "actualizar".
                if os.path.exists(ruta_destino):
                    os.remove(ruta_destino)
                
                shutil.move(ruta_origen, ruta_destino)
                print(f"✅ {msg}")
            except Exception as e:
                print(f"⚠️ Error al enrutar {f}: {e}")

print(f"👁️‍VIGILANTE AVRORA PRO ACTIVO")
print(f"Enrutando main.dart a lib/ y pubspec a raíz.")

try:
    while True:
        mover()
        time.sleep(2)
except KeyboardInterrupt:
    print("\n🛑 Vigilante detenido.")