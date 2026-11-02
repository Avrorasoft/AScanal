import requests
import os
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def publicar_en_archive_forzado(ruta_archivo, item_id, titulo_video):
    ACCESS = "X8X9EN1c2EX2kEzq"
    SECRET = "8g1jFLmXyex3DXAq"
    
    # FORZAMOS LA IP DIRECTA DEL SERVIDOR S3 DE ARCHIVE.ORG
    # Esto evita que el error "Failed to resolve" nos detenga
    ip_servidor = "207.241.232.222"
    url = f"https://{ip_servidor}/{item_id}/{os.path.basename(ruta_archivo)}"
    
    headers = {
        "Authorization": f"LOW {ACCESS}:{SECRET}",
        "Host": "s3.archive.org", # IMPORTANTE: Le decimos al servidor quiénes somos
        "x-archive-meta-collection": "opensource_media",
        "x-archive-meta-mediatype": "movies",
        "x-archive-meta-title": titulo_video,
        "x-archive-auto-make-bucket": "1" 
    }

    try:
        print(f"\n[*] MODO EVASIÓN: Subiendo vía IP Directa {ip_servidor}...")
        with open(ruta_archivo, 'rb') as f:
            # Con el túnel WARP activo, esto debería volar
            r = requests.put(url, headers=headers, data=f, timeout=60, verify=False)
        
        if r.status_code == 200:
            print(f"[+] ¡LO LOGRAMOS, RAMIRO! Publicado con éxito.")
            return True
        else:
            print(f"[!] El servidor respondió ({r.status_code}): {r.text}")
            return False
            
    except Exception as e:
        print(f"[!] Error de conexión incluso con IP fija: {e}")
        return False

if __name__ == "__main__":
    print("======================================================")
    print("  SISTEMA DE EMERGENCIA - CANAL 9 TVA")
    print("======================================================")
    
    nombre_test = "pulso_final.txt"
    with open(nombre_test, "w") as f:
        f.write("Sincronizacion forzada exitosa desde Riberalta.")
    
    publicar_en_archive_forzado(nombre_test, "canal-9-tva-riberalta-test", "Prueba Final Evasion")
    
    if os.path.exists(nombre_test):
        os.remove(nombre_test)
    print("======================================================")