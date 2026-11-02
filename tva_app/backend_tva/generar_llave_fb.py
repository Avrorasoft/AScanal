import pickle
import time
from selenium import webdriver

def crear_llave_maestra():
    print("==================================================")
    print(" AVRORA SOFT - VIBOLA LLC | GENERADOR DE LLAVE FB")
    print("==================================================")
    print("[*] Levantando navegador táctico para inicio de sesión...")
    
    # Abrimos Chrome EN MODO VISIBLE (sin --headless)
    driver = webdriver.Chrome()
    driver.get("https://mbasic.facebook.com")
    
    print("\n[!] ACCIÓN REQUERIDA:")
    print("    1. Ve a la ventana de Chrome que se acaba de abrir.")
    print("    2. Inicia sesión con tu cuenta de Facebook (o una cuenta designada para el sistema).")
    print("    3. Si Facebook te pregunta '¿Guardar navegador?' o 'Aceptar cookies', presiona Aceptar.")
    print("    4. Una vez que estés viendo el muro de inicio, regresa a esta terminal.")
    
    # Pausamos el script hasta que el usuario confirme
    input("\n[!] Presiona ENTER aquí en la terminal cuando hayas iniciado sesión...")
    
    print("[*] Extrayendo sesión activa...")
    cookies = driver.get_cookies()
    
    with open("cookies_fb.pkl", "wb") as archivo:
        pickle.dump(cookies, archivo)
        
    print(f"[+] ¡Llave maestra generada con éxito! ({len(cookies)} cookies guardadas)")
    print("[*] Archivo 'cookies_fb.pkl' creado. Ya puedes cerrar esta terminal.")
    driver.quit()

if __name__ == "__main__":
    crear_llave_maestra()