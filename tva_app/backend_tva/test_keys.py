import requests
import os

# =====================================================================
# AVRORA SOFT - VIBOLA LLC | AUDITORÍA POST-TÚNEL (WARP ACTIVE)
# Proyecto: CANAL 9 TVA - TELEVISIÓN AMAZÓNICA-RIBERALTA
# =====================================================================

ARCHIVE_ACCESS_KEY = "X8X9EN1c2EX2kEzq"
ARCHIVE_SECRET_KEY = "8g1jFLmXyex3DXAq"

def probar_con_warp():
    print("======================================================")
    print("  AUDITORÍA CON CLOUDFLARE WARP - CANAL 9 TVA")
    print("======================================================")
    
    archivo_prueba = "prueba_warp.txt"
    with open(archivo_prueba, "w") as f:
        f.write("Si lees esto, el túnel de Cloudflare derrotó al bloqueo.")

    # Volvemos al host oficial, WARP se encarga del resto
    item_id = "canal-9-tva-riberalta-test" 
    url = f"https://s3.archive.org/{item_id}/{archivo_prueba}"
    
    headers = {
        "Authorization": f"LOW {ARCHIVE_ACCESS_KEY}:{ARCHIVE_SECRET_KEY}",
        "x-archive-meta-collection": "opensource_media",
        "x-archive-meta-title": "Sincronizacion Exitosa WARP"
    }

    print(f"[*] Intentando subir a través del túnel: {url}")
    
    try:
        with open(archivo_prueba, 'rb') as f:
            # Con WARP, la respuesta debería ser rápida
            r = requests.put(url, headers=headers, data=f, timeout=20)
        
        if r.status_code == 200:
            print("\n[+] ¡LO LOGRAMOS, RAMIRO! El túnel está operativo.")
            print("[+] Las llaves son correctas y el bloqueo ha sido evadido.")
        else:
            print(f"\n[!] El servidor respondió con error {r.status_code}")
            print(f"[*] Detalle: {r.text}")
            
    except Exception as e:
        print(f"\n[!] Error de conexión: {e}")
        print("\n[*] NOTA: Asegúrate de que el icono de WARP diga 'CONNECTED'.")
    finally:
        if os.path.exists(archivo_prueba): os.remove(archivo_prueba)

if __name__ == "__main__":
    probar_con_warp()