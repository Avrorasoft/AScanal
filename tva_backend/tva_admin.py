# -*- coding: utf-8 -*-
import os
import time
from datetime import datetime
from urllib.parse import urlparse
from flask import Flask, render_template_string, request, redirect, url_for, send_from_directory, jsonify, abort
from werkzeug.utils import secure_filename
import firebase_admin
from firebase_admin import credentials, db, messaging

app = Flask(__name__)

# Permitir archivos grandes de video (hasta 500 MB)
app.config['MAX_CONTENT_LENGTH'] = 500 * 1024 * 1024

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
VOD_FOLDER = os.path.join(BASE_DIR, "vod_local")
os.makedirs(VOD_FOLDER, exist_ok=True)

SEARCH_MEDIA_DIRS = [
    VOD_FOLDER,
    BASE_DIR,
    r"C:\Canal9\tva_backend\vod_local",
    r"C:\Canal9\tva_backend",
    r"C:\tva_backend\vod_local",
    r"C:\tva_backend",
    r"C:\Canal9\tva_app\backend_tva\temp_tva"
]

IP_SERVIDOR_LOCAL = "192.168.0.104"
PUERTO_LOCAL = 5000
BASE_URL_LOCAL = f"http://{IP_SERVIDOR_LOCAL}:{PUERTO_LOCAL}"

LAT_RIBERALTA = -11.0064
LON_RIBERALTA = -66.0636

FIREBASE_DB_URL = "https://canal-9-tva-fe8dc-default-rtdb.firebaseio.com"

CRED_PATHS = [
    os.path.join(BASE_DIR, "firebase_admin.json"),
    r"C:\Canal9\tva_backend\firebase_admin.json",
    r"C:\tva_backend\firebase_admin.json"
]

firebase_conectado = False
for c_path in CRED_PATHS:
    if os.path.exists(c_path):
        try:
            if not firebase_admin._apps:
                cred = credentials.Certificate(c_path)
                firebase_admin.initialize_app(cred, {"databaseURL": FIREBASE_DB_URL})
            firebase_conectado = True
            print("[AVRORA SOFT] Conexión satelital a Firebase establecida.")
            break
        except Exception as e:
            print(f"[ERROR FIREBASE] {e}")

if not firebase_conectado:
    print("[ADVERTENCIA] No se encontró firebase_admin.json. Operando en modo contingencia local.")

MESES_ES = {
    1: "ene", 2: "feb", 3: "mar", 4: "abr", 5: "may", 6: "jun",
    7: "jul", 8: "ago", 9: "sep", 10: "oct", 11: "nov", 12: "dic"
}

def fecha_legible_actual():
    ahora = datetime.now()
    return f"{ahora.day:02d} de {MESES_ES[ahora.month]} {ahora.year}"

def buscar_archivo_en_disco(nombre_archivo):
    if not nombre_archivo:
        return None, None
    limpio = os.path.basename(nombre_archivo.strip())
    for carpeta in SEARCH_MEDIA_DIRS:
        if os.path.isdir(carpeta):
            ruta_completa = os.path.join(carpeta, limpio)
            if os.path.isfile(ruta_completa):
                return carpeta, limpio
    return None, None

def resolver_url_multimedia(url_original):
    if not url_original:
        return ""
    url_str = str(url_original).strip()
    if not url_str:
        return ""
    try:
        parsed = urlparse(url_str)
        nombre = os.path.basename(parsed.path) if parsed.path else os.path.basename(url_str)
    except Exception:
        nombre = os.path.basename(url_str)

    carpeta, archivo = buscar_archivo_en_disco(nombre)
    if carpeta and archivo:
        return f"/vod_local/{archivo}"

    if "192.168.1.10" in url_str or "127.0.0.1" in url_str or "localhost" in url_str:
        if nombre:
            return f"/vod_local/{nombre}"
    return url_str

def obtener_config_emision():
    default_cfg = {
        "global_open": False,
        "radio_km": 50,
        "lat_origen": LAT_RIBERALTA,
        "lon_origen": LON_RIBERALTA,
        "restriccion_fronteriza": True,
        "pais_permitido": "BO",
        "paises_bloqueados": ["BR", "PE"],
        "bloquear_brasil": True,
        "bloquear_peru": True,
        "ultima_sync": "Sin registro"
    }
    if not firebase_conectado:
        return default_cfg
    try:
        ref = db.reference("admin_config")
        data = ref.get()
        if isinstance(data, dict):
            default_cfg.update(data)
    except Exception as e:
        print(f"[ERROR LECTURA CONFIG] {e}")
    return default_cfg

def obtener_noticias():
    noticias_lista = []
    if not firebase_conectado:
        return noticias_lista
    try:
        ref = db.reference("noticias")
        data = ref.get()
        if isinstance(data, dict):
            for k, v in data.items():
                if isinstance(v, dict):
                    item = dict(v)
                    item["id"] = str(item.get("id") or k)
                    item["key_db"] = str(k)
                    item["titulo"] = item.get("titulo", "Sin título")
                    item["categoria"] = item.get("categoria", "LOCAL")
                    item["descripcion"] = item.get("descripcion", "")
                    item["cuerpo_unificado"] = item.get("cuerpo_completo") or item.get("cuerpo") or ""
                    item["fecha_mostrar"] = item.get("fecha") or item.get("fecha_str") or "Reciente"
                    item["vistos"] = int(item.get("vistos", 0) or 0)
                    item["bueno"] = int(item.get("bueno", 0) or 0)
                    item["feliz"] = int(item.get("feliz", 0) or 0)
                    item["likes"] = int(item.get("likes", 0) or 0)
                    item["fijado"] = bool(item.get("fijado", False))

                    raw_video = item.get("videoUrl") or item.get("video") or ""
                    raw_audio = item.get("audioUrl") or item.get("audio") or ""
                    raw_img = item.get("imagen") or ""

                    item["videoUrl_raw"] = raw_video
                    item["audioUrl_raw"] = raw_audio
                    item["imagen_raw"] = raw_img

                    item["video_play"] = resolver_url_multimedia(raw_video)
                    item["audio_play"] = resolver_url_multimedia(raw_audio)
                    item["imagen_play"] = resolver_url_multimedia(raw_img)

                    nombre_vid = os.path.basename(urlparse(raw_video).path) if raw_video else ""
                    carpeta_v, _ = buscar_archivo_en_disco(nombre_vid)
                    item["en_disco_local"] = bool(carpeta_v)

                    orden_id = 0
                    try:
                        orden_id = int("".join(ch for ch in str(k) if ch.isdigit())[:14] or 0)
                    except Exception:
                        orden_id = int(item.get("timestamp", 0) or 0)
                    item["orden_num"] = orden_id

                    noticias_lista.append(item)

        noticias_lista.sort(
            key=lambda x: (x.get("fijado", False), x.get("orden_num", 0)),
            reverse=True
        )
    except Exception as e:
        print(f"[ERROR LECTURA NOTICIAS] {e}")
    return noticias_lista

def obtener_usuarios():
    usuarios_lista = []
    if not firebase_conectado:
        return usuarios_lista
    try:
        ref = db.reference("seguridad_usuarios")
        data = ref.get()
        if isinstance(data, dict):
            for k, v in data.items():
                if isinstance(v, dict):
                    u = dict(v)
                    u["key"] = k
                    usuarios_lista.append(u)
    except Exception as e:
        print(f"[ERROR LECTURA USUARIOS] {e}")
    return usuarios_lista

def disparar_fcm_sync(motivo="actualizacion_general"):
    if not firebase_conectado:
        return False
    try:
        msg = messaging.Message(
            data={
                "accion": "sincronizar_vod",
                "motivo": motivo,
                "timestamp": str(int(time.time()))
            },
            topic="tva_general"
        )
        messaging.send(msg)
        return True
    except Exception as e:
        print(f"[AVISO FCM] {e}")
        return False

HTML_PANEL = """
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CANAL 9 TVA - TELEVISIÓN AMAZÓNICA - RIBERALTA</title>
    <link rel="stylesheet" href="https://cdn.datatables.net/1.13.6/css/jquery.dataTables.min.css">
    <style>
        :root {
            --bg-dark: #07090e;
            --card-dark: #111622;
            --border-col: #1f293d;
            --cyan: #00f0ff;
            --fuchsia: #ff007f;
            --amber: #ffb703;
            --green: #00e676;
            --text-main: #f1f5f9;
            --text-muted: #94a3b8;
        }
        * { box-sizing: border-box; }
        body {
            background-color: var(--bg-dark);
            color: var(--text-main);
            font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            margin: 0;
            padding: 20px;
        }
        .topbar {
            background: linear-gradient(90deg, #0d1321 0%, #151c2e 100%);
            border: 1px solid var(--border-col);
            border-left: 6px solid var(--cyan);
            border-radius: 10px;
            padding: 18px 24px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 15px;
            margin-bottom: 24px;
            box-shadow: 0 8px 24px rgba(0,0,0,0.6);
        }
        .brand h1 {
            margin: 0;
            font-size: 22px;
            letter-spacing: 0.8px;
            color: var(--cyan);
            text-transform: uppercase;
        }
        .brand p {
            margin: 4px 0 0 0;
            font-size: 13px;
            color: var(--text-muted);
        }
        .status-badges {
            display: flex;
            gap: 12px;
            align-items: center;
            flex-wrap: wrap;
        }
        .badge {
            padding: 8px 14px;
            border-radius: 6px;
            font-size: 12px;
            font-weight: 700;
            letter-spacing: 0.5px;
            text-transform: uppercase;
        }
        .badge-online { background: rgba(0, 230, 118, 0.15); color: var(--green); border: 1px solid var(--green); }
        .badge-ip { background: rgba(0, 240, 255, 0.12); color: var(--cyan); border: 1px solid var(--cyan); }
        .badge-amber { background: rgba(255, 183, 3, 0.15); color: var(--amber); border: 1px solid var(--amber); }
        .badge-fuchsia { background: rgba(255, 0, 127, 0.15); color: var(--fuchsia); border: 1px solid var(--fuchsia); }

        .grid-top {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 20px;
            margin-bottom: 24px;
        }
        .card {
            background-color: var(--card-dark);
            border: 1px solid var(--border-col);
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 6px 18px rgba(0,0,0,0.45);
        }
        .card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid var(--border-col);
            padding-bottom: 12px;
            margin-bottom: 16px;
            flex-wrap: wrap;
            gap: 8px;
        }
        .card-header h2 {
            margin: 0;
            font-size: 16px;
            color: var(--cyan);
            text-transform: uppercase;
            letter-spacing: 0.6px;
        }
        .form-group {
            margin-bottom: 12px;
        }
        label {
            display: block;
            font-size: 12px;
            color: var(--text-muted);
            margin-bottom: 5px;
            font-weight: 600;
        }
        input[type="text"], input[type="number"], textarea, select, input[type="file"] {
            width: 100%;
            background: #090d16;
            border: 1px solid #2a364f;
            color: var(--text-main);
            padding: 9px 12px;
            border-radius: 6px;
            font-size: 13px;
        }
        input[type="range"] {
            width: 100%;
            accent-color: var(--fuchsia);
            cursor: pointer;
        }
        textarea { resize: vertical; min-height: 70px; }
        .range-display {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-top: 6px;
            font-size: 13px;
            font-weight: bold;
            color: var(--amber);
        }
        .btn {
            display: inline-block;
            padding: 10px 16px;
            border-radius: 6px;
            font-size: 12px;
            font-weight: 700;
            text-transform: uppercase;
            text-decoration: none;
            cursor: pointer;
            border: none;
            transition: opacity 0.2s;
        }
        .btn:hover { opacity: 0.88; }
        .btn-cyan { background-color: var(--cyan); color: #000; }
        .btn-fuchsia { background-color: var(--fuchsia); color: #fff; }
        .btn-green { background-color: var(--green); color: #000; }
        .btn-amber { background-color: var(--amber); color: #000; }
        .btn-danger { background-color: #ef4444; color: #fff; }
        .btn-sm { padding: 6px 10px; font-size: 11px; margin-bottom: 4px; }

        .switch-row {
            display: flex;
            align-items: center;
            justify-content: space-between;
            background: #0b101b;
            padding: 10px 14px;
            border-radius: 8px;
            border: 1px solid #1e293b;
            margin-bottom: 10px;
        }
        .switch-row span { font-weight: 600; font-size: 13px; }
        .border-box {
            background: #090d16;
            border: 1px solid #263248;
            border-left: 4px solid var(--fuchsia);
            border-radius: 8px;
            padding: 12px;
            margin-bottom: 14px;
        }
        .border-box-title {
            font-size: 12px;
            font-weight: 700;
            color: var(--fuchsia);
            text-transform: uppercase;
            margin-bottom: 10px;
            letter-spacing: 0.5px;
        }

        table.dataTable {
            width: 100% !important;
            border-collapse: collapse !important;
            color: var(--text-main) !important;
            font-size: 13px;
        }
        table.dataTable thead th {
            background-color: #0b0f19 !important;
            color: var(--cyan) !important;
            border-bottom: 1px solid var(--border-col) !important;
            padding: 10px !important;
            text-align: left;
        }
        table.dataTable tbody tr {
            background-color: var(--card-dark) !important;
            border-bottom: 1px solid #1a2234 !important;
        }
        table.dataTable tbody td {
            padding: 10px !important;
            vertical-align: middle;
        }
        .dataTables_wrapper .dataTables_filter input,
        .dataTables_wrapper .dataTables_length select {
            background: #090d16 !important;
            color: #fff !important;
            border: 1px solid #2a364f !important;
            border-radius: 4px;
            padding: 4px 8px;
        }
        .dataTables_wrapper .dataTables_info,
        .dataTables_wrapper .dataTables_paginate {
            color: var(--text-muted) !important;
            margin-top: 10px;
        }
        .pill-fijado {
            background: var(--fuchsia);
            color: #fff;
            padding: 3px 8px;
            border-radius: 4px;
            font-size: 10px;
            font-weight: bold;
            display: inline-block;
            margin-bottom: 4px;
        }
        .pill-cat {
            background: #1e293b;
            color: var(--cyan);
            border: 1px solid var(--cyan);
            padding: 2px 7px;
            border-radius: 4px;
            font-size: 10px;
            font-weight: bold;
            display: inline-block;
        }
        .media-box {
            display: flex;
            flex-direction: column;
            gap: 6px;
            min-width: 250px;
        }
        .video-player {
            width: 250px;
            height: 140px;
            background: #000;
            border-radius: 6px;
            border: 1px solid #2a364f;
            object-fit: cover;
        }
        .thumb-mini {
            width: 72px;
            height: 48px;
            object-fit: cover;
            border-radius: 4px;
            border: 1px solid var(--cyan);
        }
        .stats-line {
            font-size: 11px;
            color: var(--amber);
            margin-top: 4px;
            font-weight: 600;
        }
    </style>
</head>
<body>

    <div class="topbar">
        <div class="brand">
            <h1>CANAL 9 TVA - TELEVISIÓN AMAZÓNICA - RIBERALTA</h1>
            <p>[AVRORA SOFT] Centro de Comando Master, Distancias de Emisión Controlada y Cerco Geográfico Soberano</p>
        </div>
        <div class="status-badges">
            <span class="badge badge-ip">IP vMix / Servidor: {{ ip_local }}:{{ puerto }}</span>
            <span class="badge badge-fuchsia">Soberanía: Solo Bolivia (BO)</span>
            {% if firebase_ok %}
                <span class="badge badge-online">Firebase Satelital: ACTIVO</span>
            {% else %}
                <span class="badge badge-amber">Firebase: MODO LOCAL</span>
            {% endif %}
            <form action="/sincronizar_forzado" method="POST" style="margin:0;">
                <button type="submit" class="btn btn-fuchsia">⚡ Sincronización Forzada (FCM)</button>
            </form>
        </div>
    </div>

    <div class="grid-top">
        <!-- PANEL 1: DISTANCIAS DE EMISIÓN CONTROLADA Y FRONTERAS -->
        <div class="card">
            <div class="card-header">
                <h2>📡 Distancias de Emisión Controlada</h2>
                <span class="badge badge-amber">Radio: {{ config.get('radio_km', 50) }} KM | Base: Riberalta</span>
            </div>
            <form action="/actualizar_config" method="POST">
                <div class="switch-row">
                    <span>🌐 Señal Global Abierta (Ignorar Radio en KM)</span>
                    <input type="checkbox" name="global_open" style="width:18px; height:18px;" {% if config.get('global_open') %}checked{% endif %}>
                </div>

                <div class="form-group">
                    <label for="radio_km">Perímetro de Cobertura Nacional (Eje Riberalta: {{ config.get('lat_origen', -11.0064) }}, {{ config.get('lon_origen', -66.0636) }}):</label>
                    <input type="range" id="radio_km" name="radio_km" min="10" max="1000" step="5" value="{{ config.get('radio_km', 50) }}" oninput="document.getElementById('km_val').innerText = this.value + ' KM'">
                    <div class="range-display">
                        <span>Mín: 10 KM (Urbano)</span>
                        <span id="km_val" style="color:var(--cyan); font-size:16px;">{{ config.get('radio_km', 50) }} KM</span>
                        <span>Máx: 1000 KM (Nacional BO)</span>
                    </div>
                </div>

                <div class="border-box">
                    <div class="border-box-title">🛡️ Cerco Fronterizo Internacional (Geofencing Soberano — País Permitido: BO)</div>
                    <div class="switch-row" style="margin-bottom:8px;">
                        <span>Activar Corte Estricto en Frontera Internacional</span>
                        <input type="checkbox" name="restriccion_fronteriza" style="width:18px; height:18px;" {% if config.get('restriccion_fronteriza', True) %}checked{% endif %}>
                    </div>
                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:10px;">
                        <div class="switch-row" style="margin-bottom:0;">
                            <span>🚫 Bloquear Brasil (BR)</span>
                            <input type="checkbox" name="bloquear_brasil" style="width:18px; height:18px;" {% if config.get('bloquear_brasil', True) %}checked{% endif %}>
                        </div>
                        <div class="switch-row" style="margin-bottom:0;">
                            <span>🚫 Bloquear Perú (PE)</span>
                            <input type="checkbox" name="bloquear_peru" style="width:18px; height:18px;" {% if config.get('bloquear_peru', True) %}checked{% endif %}>
                        </div>
                    </div>
                    <div style="font-size:11px; color:var(--text-muted); margin-top:8px;">
                        * La señal se corta automáticamente al cruzar los ríos Mamoré / Abuná (Rondônia - Acre, Brasil) o el eje Madre de Dios (Perú), aunque el dispositivo esté dentro del radio en kilómetros.
                    </div>
                </div>

                <div class="form-group">
                    <div style="background:#090d16; padding:10px; border-radius:6px; border:1px solid #1f293d; font-size:12px; color:var(--green);">
                        ✔ Red vMix sincronizada en <strong>{{ ip_local }}</strong> | Bloqueo activo: <strong>{{ config.get('paises_bloqueados', ['BR', 'PE'])|join(', ') }}</strong> | Sync: <span style="color:var(--text-muted);">{{ config.get('ultima_sync', 'Reciente') }}</span>
                    </div>
                </div>

                <button type="submit" class="btn btn-cyan" style="width:100%;">Guardar Parámetros y Cerco Fronterizo</button>
            </form>
        </div>

        <!-- PANEL 2: PUBLICAR / EDITAR CONTENIDO VOD (CON ENCTYPE MULTIPART OBLIGATORIO) -->
        <div class="card">
            <div class="card-header">
                <h2>🎬 {% if edit_item %}Editar Reportaje ({{ edit_item.id }}){% else %}Publicar Nuevo Material VOD / Noticia{% endif %}</h2>
                {% if edit_item %}
                    <a href="/" class="btn btn-amber btn-sm">Cancelar Edición</a>
                {% endif %}
            </div>
            <form action="{% if edit_item %}/editar/{{ edit_item.key_db }}{% else %}/nuevo{% endif %}" method="POST" enctype="multipart/form-data">
                <div style="display:grid; grid-template-columns: 2fr 1fr; gap:10px;">
                    <div class="form-group">
                        <label>Título del Reportaje / Noticia:</label>
                        <input type="text" name="titulo" required placeholder="Ej: Informativo Meridiano - Canal 9 TVA" value="{{ edit_item.titulo if edit_item else '' }}">
                    </div>
                    <div class="form-group">
                        <label>Categoría:</label>
                        {% set cat_actual = edit_item.categoria if edit_item else 'LOCAL' %}
                        <select name="categoria">
                            <option value="LOCAL" {% if cat_actual == 'LOCAL' %}selected{% endif %}>LOCAL (Riberalta / Beni)</option>
                            <option value="NACIONAL" {% if cat_actual == 'NACIONAL' %}selected{% endif %}>NACIONAL (Bolivia)</option>
                            <option value="INTERNACIONAL" {% if cat_actual == 'INTERNACIONAL' %}selected{% endif %}>INTERNACIONAL</option>
                            <option value="DEPORTES" {% if cat_actual == 'DEPORTES' %}selected{% endif %}>DEPORTES</option>
                            <option value="ESPECIAL" {% if cat_actual == 'ESPECIAL' %}selected{% endif %}>ESPECIAL TVA</option>
                        </select>
                    </div>
                </div>

                <div class="form-group">
                    <label>Descripción Breve (Subtítulo / Copete):</label>
                    <input type="text" name="descripcion" placeholder="Resumen ejecutivo para la tarjeta móvil" value="{{ edit_item.descripcion if edit_item else '' }}">
                </div>

                <div class="form-group">
                    <label>Cuerpo Completo de la Nota (cuerpo_completo / cuerpo):</label>
                    <textarea name="cuerpo_completo" placeholder="Desarrollo completo de la noticia...">{{ edit_item.cuerpo_unificado if edit_item else '' }}</textarea>
                </div>

                <div style="display:grid; grid-template-columns: 1fr 1fr 1fr; gap:10px;">
                    <div class="form-group">
                        <label>Video (.mp4) o URL (videoUrl):</label>
                        <input type="file" name="archivo_video" accept="video/*">
                        <input type="text" name="videoUrl" placeholder="https://vod.canal9.top/..." style="margin-top:5px;" value="{{ edit_item.videoUrl_raw if edit_item else '' }}">
                    </div>
                    <div class="form-group">
                        <label>Miniatura (.webp/.jpg) o URL (imagen):</label>
                        <input type="file" name="archivo_imagen" accept="image/*">
                        <input type="text" name="imagen" placeholder="https://vod.canal9.top/..." style="margin-top:5px;" value="{{ edit_item.imagen_raw if edit_item else '' }}">
                    </div>
                    <div class="form-group">
                        <label>Audio (.mp3/.wav) o URL (audioUrl):</label>
                        <input type="file" name="archivo_audio" accept="audio/*">
                        <input type="text" name="audioUrl" placeholder="URL de audio opcional..." style="margin-top:5px;" value="{{ edit_item.audioUrl_raw if edit_item else '' }}">
                    </div>
                </div>

                <div class="switch-row">
                    <span>📌 Fijar este contenido como Destacado Principal en la App</span>
                    <input type="checkbox" name="fijado" style="width:18px; height:18px;" {% if edit_item and edit_item.fijado %}checked{% endif %}>
                </div>

                <button type="submit" class="btn btn-green" style="width:100%;">
                    {% if edit_item %}Guardar Cambios en Firebase{% else %}Publicar Material y Notificar a Dispositivos{% endif %}
                </button>
            </form>
        </div>
    </div>

    <!-- TABLA 1: CATÁLOGO DE REPORTAJES Y REPRODUCTOR VOD INTEGRADO -->
    <div class="card" style="margin-bottom: 24px;">
        <div class="card-header">
            <h2>📺 Catálogo de Emisiones y Reproductor VOD Directo ({{ noticias|length }})</h2>
            <span style="font-size:12px; color:var(--text-muted);">Almacenamiento local: C:\Canal9\tva_backend\vod_local | Dominio: vod.canal9.top</span>
        </div>
        <table id="tablaVod" class="display">
            <thead>
                <tr>
                    <th>Categoría / ID</th>
                    <th>Portada y Título</th>
                    <th>Reproductor de Video / Audio</th>
                    <th>Métricas App</th>
                    <th>Fecha</th>
                    <th>Acciones</th>
                </tr>
            </thead>
            <tbody>
                {% for n in noticias %}
                <tr>
                    <td>
                        {% if n.fijado %}
                            <span class="pill-fijado">📌 FIJADO</span><br>
                        {% endif %}
                        <span class="pill-cat">{{ n.categoria }}</span>
                        <div style="font-size:11px; color:var(--text-muted); margin-top:4px;">ID: {{ n.id }}</div>
                    </td>
                    <td>
                        <div style="display:flex; gap:10px; align-items:flex-start;">
                            {% if n.imagen_play %}
                                <img src="{{ n.imagen_play }}" class="thumb-mini" alt="Miniatura" onerror="this.style.display='none'">
                            {% endif %}
                            <div>
                                <strong style="font-size:14px; color:#fff;">{{ n.titulo }}</strong>
                                {% if n.descripcion %}
                                    <div style="font-size:12px; color:var(--text-muted); margin-top:3px;">{{ n.descripcion }}</div>
                                {% endif %}
                                {% if n.cuerpo_unificado %}
                                    <div style="font-size:11px; color:#64748b; margin-top:3px;">{{ n.cuerpo_unificado[:90] }}{% if n.cuerpo_unificado|length > 90 %}...{% endif %}</div>
                                {% endif %}
                            </div>
                        </div>
                    </td>
                    <td>
                        <div class="media-box">
                            {% if n.video_play %}
                                <video class="video-player" controls preload="metadata" {% if n.imagen_play %}poster="{{ n.imagen_play }}"{% endif %}>
                                    <source src="{{ n.video_play }}" type="video/mp4">
                                    Tu navegador no soporta reproducción HTML5.
                                </video>
                                <div style="display:flex; justify-content:space-between; align-items:center; font-size:11px;">
                                    <a href="{{ n.video_play }}" target="_blank" style="color:var(--cyan); text-decoration:none; font-weight:bold;">🔗 Abrir enlace directo</a>
                                    {% if n.en_disco_local %}
                                        <span style="color:var(--green);">● En Disco Local</span>
                                    {% else %}
                                        <span style="color:var(--amber);" title="Apunta a vod.canal9.top (Requiere túnel o R2 activo)">● Remoto (vod.canal9.top)</span>
                                    {% endif %}
                                </div>
                            {% else %}
                                <span style="color:var(--text-muted); font-size:12px;">Sin video asignado</span>
                            {% endif %}

                            {% if n.audio_play %}
                                <audio controls preload="none" style="width:250px; height:32px; margin-top:4px;">
                                    <source src="{{ n.audio_play }}">
                                </audio>
                            {% endif %}
                        </div>
                    </td>
                    <td>
                        <div class="stats-line">👁️ Vistos: {{ n.vistos }}</div>
                        <div style="font-size:11px; color:var(--text-muted); margin-top:4px;">
                            👍 Bueno: {{ n.bueno }} | 😊 Feliz: {{ n.feliz }} | ❤️ Likes: {{ n.likes }}
                        </div>
                    </td>
                    <td>{{ n.fecha_mostrar }}</td>
                    <td>
                        <a href="/?editar={{ n.key_db }}" class="btn btn-amber btn-sm">Editar</a><br>
                        <a href="/borrar/{{ n.key_db }}" class="btn btn-danger btn-sm" onclick="return confirm('¿Seguro que deseas eliminar este reportaje de Firebase?');">Borrar</a>
                    </td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>

    <!-- TABLA 2: PADRÓN DE CIUDADANOS INSCRITOS Y SEGURIDAD -->
    <div class="card">
        <div class="card-header">
            <h2>🛡️ Padrón de Ciudadanos Inscritos y Control WhatsApp ({{ usuarios|length }})</h2>
            <span style="font-size:12px; color:var(--text-muted);">Nodo Firebase: seguridad_usuarios</span>
        </div>
        <table id="tablaUsuarios" class="display">
            <thead>
                <tr>
                    <th>Nombre Real</th>
                    <th>Apodo / Alias</th>
                    <th>WhatsApp</th>
                    <th>Código / Token</th>
                    <th>Acción Disciplinaria</th>
                </tr>
            </thead>
            <tbody>
                {% for u in usuarios %}
                <tr>
                    <td><strong>{{ u.get('nombre_real', u.get('nombre', 'No especificado')) }}</strong></td>
                    <td style="color:var(--cyan);">{{ u.get('apodo', 'Sin alias') }}</td>
                    <td>
                        {% if u.get('whatsapp') %}
                            <a href="https://wa.me/{{ u.get('whatsapp')|replace('+','')|replace(' ','') }}" target="_blank" style="color:var(--green); text-decoration:none; font-weight:bold;">
                                📱 {{ u.get('whatsapp') }}
                            </a>
                        {% else %}
                            <span style="color:var(--text-muted);">No registrado</span>
                        {% endif %}
                    </td>
                    <td><code>{{ u.get('codigo', u.get('key', '')) }}</code></td>
                    <td>
                        <a href="/borrar_usuario/{{ u.key }}" class="btn btn-danger btn-sm" onclick="return confirm('¿Expulsar y borrar a este ciudadano del padrón?');">Expulsar</a>
                    </td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>

    <script src="https://code.jquery.com/jquery-3.7.0.min.js"></script>
    <script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
    <script>
        .ready(function() {
            #tablaVod.DataTable({
                pageLength: 10,
                order: [],
                language: {
                    search: "Buscar por título o categoría:",
                    lengthMenu: "Mostrar _MENU_ reportajes",
                    info: "Mostrando _START_ a _END_ de _TOTAL_ reportajes",
                    emptyTable: "No hay materiales VOD registrados en Firebase.",
                    paginate: { first: "Primero", last: "Último", next: "Siguiente", previous: "Anterior" }
                }
            });
            #tablaUsuarios.DataTable({
                pageLength: 10,
                language: {
                    search: "Buscar ciudadano / WhatsApp:",
                    lengthMenu: "Mostrar _MENU_ ciudadanos",
                    info: "Mostrando _START_ a _END_ de _TOTAL_ ciudadanos",
                    emptyTable: "No hay ciudadanos registrados en seguridad_usuarios.",
                    paginate: { first: "Primero", last: "Último", next: "Siguiente", previous: "Anterior" }
                }
            });
        });
    </script>
</body>
</html>
"""

@app.route("/")
def index():
    config = obtener_config_emision()
    noticias = obtener_noticias()
    usuarios = obtener_usuarios()

    edit_id = request.args.get("editar")
    edit_item = None
    if edit_id:
        for n in noticias:
            if str(n.get("key_db")) == str(edit_id) or str(n.get("id")) == str(edit_id):
                edit_item = n
                break

    return render_template_string(
        HTML_PANEL,
        config=config,
        noticias=noticias,
        usuarios=usuarios,
        edit_item=edit_item,
        ip_local=IP_SERVIDOR_LOCAL,
        puerto=PUERTO_LOCAL,
        firebase_ok=firebase_conectado
    )

@app.route("/actualizar_config", methods=["POST"])
def actualizar_config():
    global_open = "global_open" in request.form
    restriccion_fronteriza = "restriccion_fronteriza" in request.form
    bloquear_brasil = "bloquear_brasil" in request.form
    bloquear_peru = "bloquear_peru" in request.form

    paises_bloqueados = []
    if bloquear_brasil:
        paises_bloqueados.append("BR")
    if bloquear_peru:
        paises_bloqueados.append("PE")

    try:
        radio_km = int(request.form.get("radio_km", 50))
    except ValueError:
        radio_km = 50

    ahora_str = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
    payload_config = {
        "global_open": global_open,
        "radio_km": radio_km,
        "lat_origen": LAT_RIBERALTA,
        "lon_origen": LON_RIBERALTA,
        "restriccion_fronteriza": restriccion_fronteriza,
        "pais_permitido": "BO",
        "paises_bloqueados": paises_bloqueados,
        "bloquear_brasil": bloquear_brasil,
        "bloquear_peru": bloquear_peru,
        "ultima_sync": ahora_str,
        "sync_timestamp": int(time.time())
    }

    if firebase_conectado:
        try:
            db.reference("admin_config").update(payload_config)
            disparar_fcm_sync("cambio_cobertura_frontera")
        except Exception as e:
            print(f"[ERROR ACTUALIZAR CONFIG] {e}")
    return redirect(url_for("index"))

@app.route("/sincronizar_forzado", methods=["POST"])
def sincronizar_forzado():
    ahora_str = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
    if firebase_conectado:
        try:
            db.reference("admin_config").update({
                "ultima_sync": ahora_str,
                "sync_timestamp": int(time.time())
            })
            disparar_fcm_sync("sincronizacion_forzada_admin")
        except Exception as e:
            print(f"[ERROR SYNC FORZADO] {e}")
    return redirect(url_for("index"))

@app.route("/nuevo", methods=["POST"])
def nuevo():
    nuevo_id = datetime.now().strftime("%Y%m%d%H%M%S")
    titulo = request.form.get("titulo", "").strip()
    categoria = request.form.get("categoria", "LOCAL").strip()
    descripcion = request.form.get("descripcion", "").strip()
    cuerpo_txt = request.form.get("cuerpo_completo", "").strip()
    video_url = request.form.get("videoUrl", "").strip()
    imagen_url = request.form.get("imagen", "").strip()
    audio_url = request.form.get("audioUrl", "").strip()
    fijado = "fijado" in request.form

    # Procesamiento y guardado seguro de video local
    archivo_video = request.files.get("archivo_video")
    if archivo_video and archivo_video.filename:
        ext_v = os.path.splitext(secure_filename(archivo_video.filename))[1] or ".mp4"
        fname_v = f"tva_vid_{nuevo_id}{ext_v}"
        ruta_salida = os.path.join(VOD_FOLDER, fname_v)
        archivo_video.save(ruta_salida)
        print(f"[VOD] Video guardado exitosamente en: {ruta_salida}")
        video_url = f"{BASE_URL_LOCAL}/vod_local/{fname_v}"

    # Procesamiento y guardado seguro de miniatura local
    archivo_imagen = request.files.get("archivo_imagen")
    if archivo_imagen and archivo_imagen.filename:
        ext_i = os.path.splitext(secure_filename(archivo_imagen.filename))[1] or ".webp"
        fname_i = f"tva_img_{nuevo_id}{ext_i}"
        ruta_salida_img = os.path.join(VOD_FOLDER, fname_i)
        archivo_imagen.save(ruta_salida_img)
        print(f"[VOD] Miniatura guardada exitosamente en: {ruta_salida_img}")
        imagen_url = f"{BASE_URL_LOCAL}/vod_local/{fname_i}"

    # Procesamiento y guardado seguro de audio local
    archivo_audio = request.files.get("archivo_audio")
    if archivo_audio and archivo_audio.filename:
        ext_a = os.path.splitext(secure_filename(archivo_audio.filename))[1] or ".mp3"
        fname_a = f"tva_aud_{nuevo_id}{ext_a}"
        ruta_salida_aud = os.path.join(VOD_FOLDER, fname_a)
        archivo_audio.save(ruta_salida_aud)
        audio_url = f"{BASE_URL_LOCAL}/vod_local/{fname_a}"

    nuevo_registro = {
        "id": nuevo_id,
        "titulo": titulo,
        "categoria": categoria,
        "descripcion": descripcion,
        "cuerpo": cuerpo_txt,
        "cuerpo_completo": cuerpo_txt,
        "videoUrl": video_url,
        "imagen": imagen_url,
        "audio": audio_url,
        "audioUrl": audio_url,
        "fijado": fijado,
        "fecha": fecha_legible_actual(),
        "vistos": 0,
        "bueno": 0,
        "feliz": 0,
        "likes": 0,
        "timestamp": int(time.time() * 1000)
    }

    if firebase_conectado:
        try:
            db.reference(f"noticias/{nuevo_id}").set(nuevo_registro)
            disparar_fcm_sync("nuevo_contenido_vod")
        except Exception as e:
            print(f"[ERROR NUEVA NOTICIA] {e}")

    return redirect(url_for("index"))

@app.route("/editar/<item_id>", methods=["POST"])
def editar(item_id):
    titulo = request.form.get("titulo", "").strip()
    categoria = request.form.get("categoria", "LOCAL").strip()
    descripcion = request.form.get("descripcion", "").strip()
    cuerpo_txt = request.form.get("cuerpo_completo", "").strip()
    video_url = request.form.get("videoUrl", "").strip()
    imagen_url = request.form.get("imagen", "").strip()
    audio_url = request.form.get("audioUrl", "").strip()
    fijado = "fijado" in request.form

    archivo_video = request.files.get("archivo_video")
    if archivo_video and archivo_video.filename:
        ext_v = os.path.splitext(secure_filename(archivo_video.filename))[1] or ".mp4"
        fname_v = f"tva_vid_{item_id}{ext_v}"
        ruta_salida = os.path.join(VOD_FOLDER, fname_v)
        archivo_video.save(ruta_salida)
        print(f"[VOD EDIT] Video actualizado en: {ruta_salida}")
        video_url = f"{BASE_URL_LOCAL}/vod_local/{fname_v}"

    archivo_imagen = request.files.get("archivo_imagen")
    if archivo_imagen and archivo_imagen.filename:
        ext_i = os.path.splitext(secure_filename(archivo_imagen.filename))[1] or ".webp"
        fname_i = f"tva_img_{item_id}{ext_i}"
        ruta_salida_img = os.path.join(VOD_FOLDER, fname_i)
        archivo_imagen.save(ruta_salida_img)
        imagen_url = f"{BASE_URL_LOCAL}/vod_local/{fname_i}"

    archivo_audio = request.files.get("archivo_audio")
    if archivo_audio and archivo_audio.filename:
        ext_a = os.path.splitext(secure_filename(archivo_audio.filename))[1] or ".mp3"
        fname_a = f"tva_aud_{item_id}{ext_a}"
        ruta_salida_aud = os.path.join(VOD_FOLDER, fname_a)
        archivo_audio.save(ruta_salida_aud)
        audio_url = f"{BASE_URL_LOCAL}/vod_local/{fname_a}"

    datos_actualizados = {
        "titulo": titulo,
        "categoria": categoria,
        "descripcion": descripcion,
        "cuerpo": cuerpo_txt,
        "cuerpo_completo": cuerpo_txt,
        "videoUrl": video_url,
        "imagen": imagen_url,
        "audio": audio_url,
        "audioUrl": audio_url,
        "fijado": fijado
    }

    if firebase_conectado:
        try:
            db.reference(f"noticias/{item_id}").update(datos_actualizados)
            disparar_fcm_sync("edicion_contenido_vod")
        except Exception as e:
            print(f"[ERROR EDITAR NOTICIA] {e}")

    return redirect(url_for("index"))

@app.route("/borrar/<item_id>")
def borrar(item_id):
    if firebase_conectado:
        try:
            db.reference(f"noticias/{item_id}").delete()
            disparar_fcm_sync("borrado_contenido_vod")
        except Exception as e:
            print(f"[ERROR BORRAR NOTICIA] {e}")
    return redirect(url_for("index"))

@app.route("/borrar_usuario/<user_key>")
def borrar_usuario(user_key):
    if firebase_conectado:
        try:
            db.reference(f"seguridad_usuarios/{user_key}").delete()
        except Exception as e:
            print(f"[ERROR BORRAR USUARIO] {e}")
    return redirect(url_for("index"))

@app.route("/vod_local/<path:filename>")
def servir_vod_local(filename):
    carpeta, archivo = buscar_archivo_en_disco(filename)
    if carpeta and archivo:
        return send_from_directory(carpeta, archivo)
    return abort(404)

@app.route("/api/status")
def api_status():
    return jsonify({
        "sistema": "CANAL 9 TVA - TELEVISIÓN AMAZÓNICA - RIBERALTA",
        "ip_local": IP_SERVIDOR_LOCAL,
        "firebase": firebase_conectado,
        "config": obtener_config_emision()
    })

if __name__ == "__main__":
    print("[SISTEMA] Servidor Local de Operaciones Avrora Soft iniciado.")
    app.run(host="0.0.0.0", port=PUERTO_LOCAL, debug=True)
