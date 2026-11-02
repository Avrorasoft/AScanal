import requests
import json

print("[IA] Conectando con Ollama local para prueba...")
prompt = "Escribe una noticia muy breve de una línea sobre Riberalta en formato JSON con los campos: titulo, descripcion."

try:
    response = requests.post(
        'http://localhost:11434/api/generate',
        json={
            "model": "llama3.2:3b",
            "prompt": prompt,
            "stream": False,
            "format": "json"
        }
    )
    if response.status_code == 200:
        resultado = json.loads(response.json()['response'])
        print("\n¡Prueba exitosa! Respuesta de la IA:")
        print(f"Título: {resultado.get('titulo')}")
        print(f"Descripción: {resultado.get('descripcion')}")
    else:
        print(f"[ERROR] Código de estado HTTP: {response.status_code}")
except Exception as e:
    print(f"[ERROR] No se pudo conectar con Ollama: {e}")