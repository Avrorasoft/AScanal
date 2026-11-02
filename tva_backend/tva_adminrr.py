import os
import json
import boto3
import time
from botocore.client import Config
from flask import Flask, render_template_string, request, redirect, url_for
import firebase_admin
from firebase_admin import credentials, messaging, db
from werkzeug.utils import secure_filename

# ==========================================================
# ADMINISTRADOR WEB CORPORATIVO - AVRORA SOFT / VIBOLA LLC
# CANAL 9 tva-TELEVISIÓN AMAZÓNICA-RIBERALTA
# ==========================================================

app = Flask(__name__)
app.secret_key = "avrora_tva_admin_secure"

PATH_JSON_LOCAL = r'C:\tva_backend\noticias.json'

# CREDENCIALES R2 (CLOUDFLARE)
R2_ACCESS_KEY = '21a17285638771b86fd7401d8e43d75b'
R2_SECRET_KEY = '82da22bcef3583cb83b6ddb4087d25f0bc98e720c745de477ca7abeb0374f20d'
R2_ENDPOINT = 'https://da292b98201102181e5228ea157e9980.r2.cloudflarestorage.com'
R2_BUCKET_NAME = 'vod-canal9'
R2_PUBLIC_URL = 'https://vod.canal9.top'

# URL DE LA BASE DE DATOS FIREBASE
FIREBASE_DB_URL = "https://canal-9-tva-fe8dc-default-rtdb.firebaseio.com"

# CONEXIÓN A R2
s3 = boto3.client('s3',
    endpoint_url=R2_ENDPOINT,
    aws_access_key_id=R2_ACCESS_KEY,
    aws_secret_access_key=R2_SECRET_KEY,
    config=Config(signature_version='s3v4'),
    region_name='auto'
)

# INICIALIZACIÓN DE FIREBASE
try:
    if not firebase_admin._apps:
        cred = credentials.Certificate(r'C:\tva_backend\firebase_admin.json')
        firebase_admin.initialize_app(cred, {
            'databaseURL': FIREBASE_DB_URL
        })
except Exception as e:
    print(f"[ERROR FIREBASE] No se pudo inicializar FCM/DB: {e}")

# ==========================================================
# FUNCIONES DE SISTEMA Y SINCRONIZACIÓN
# ==========================================================

def disparar_actualizacion_remota():
    try:
        mensaje = messaging.Message(
            data={'accion': 'forzar_actualizacion'},
            topic='tva_noticias'
        )
        messaging.send(mensaje)
        print("[FCM] Orden PUSH disparada a los dispositivos.")
    except Exception as e:
        print(f"[ERROR FCM] Falló el disparo a los teléfonos: {e}")

def sincronizar_json_r2():
    try:
        s3.upload_file(
            PATH_JSON_LOCAL, 
            R2_BUCKET_NAME, 
            "noticias.json", 
            ExtraArgs={'ContentType': 'application/json', 'CacheControl': 'no-cache, no-store, must-revalidate'}
        )
        print("[NUBE] noticias.json sincronizado correctamente.")
        disparar_actualizacion_remota()
    except Exception as e:
        print("[ERROR NUBE] Falla de sincronización:", e)

def leer_feed():
    if os.path.exists(PATH_JSON_LOCAL):
        with open(PATH_JSON_LOCAL, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {"version": 1, "feed_noticias": []}

def guardar_feed(feed):
    feed['version'] = feed.get('version', 0) + 1
    with open(PATH_JSON_LOCAL, 'w', encoding='utf-8') as f:
        json.dump(feed, f, indent=4, ensure_ascii=False)
    sincronizar_json_r2()

# ==========================================================
# INTERFAZ GRÁFICA (HTML + BOOTSTRAP + DATATABLES ESPAÑOL)
# ==========================================================

HTML_BASE = """
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>tva Admin - Panel de Control</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.datatables.net/1.13.6/css/dataTables.bootstrap5.min.css" rel="stylesheet">
    <style>
        body { background-color: #0a0a0a; color: #f8f9fa; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; }
        .navbar { background-color: #000000 !important; border-bottom: 2px solid #ff2400; }
        .table-dark { background-color: #121212; }
        .card { background-color: #1a1a1a; border: 1px solid #333; }
        .form-control, .form-check-input, .form-select { background-color: #2b2b2b; color: white; border: 1px solid #444; }
        .form-control:focus, .form-select:focus { background-color: #333; color: white; border-color: #ff2400; box-shadow: none; }
        .text-brand { color: #ff2400 !important; }
        .btn-brand { background-color: #ff2400; color: white; border: none; }
        .btn-brand:hover { background-color: #cc1d00; color: white; }
        
        /* Ajustes forzados para que DataTables sea legible en fondo oscuro */
        div.dataTables_wrapper div.dataTables_length label, 
        div.dataTables_wrapper div.dataTables_filter label,
        div.dataTables_wrapper div.dataTables_info,
        .page-link { color: white !important; font-weight: bold; }
        
        div.dataTables_wrapper div.dataTables_length select, 
        div.dataTables_wrapper div.dataTables_filter input {
            color: white !important; background-color: #2b2b2b !important; border: 1px solid #444 !important;
        }
        
        .page-item.active .page-link { background-color: #ff2400 !important; border-color: #ff2400 !important; color: white !important; }
        .page-link { background-color: #1a1a1a !important; border-color: #333 !important; }
        .page-link:hover { background-color: #333 !important; }
    </style>
</head>
<body>
    <nav class="navbar navbar-dark">
        <div class="container-fluid">
            <span class="navbar-brand mb-0 h1 fw-bold tracking-wider">CANAL 9 tva - ADMINISTRACIÓN DIGITAL</span>
        </div>
    </nav>
    <div class="container mt-4 pb-5">
        {% block content %}{% endblock %}
    </div>

    <script src="https://code.jquery.com/jquery-3.7.0.min.js"></script>
    <script src="https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js"></script>
    <script src="https://cdn.datatables.net/1.13.6/js/dataTables.bootstrap5.min.js"></script>
    <script>
        $(document).ready(function() {
            $('.tabla-dinamica').DataTable({
                "language": {
                    "sProcessing":     "Procesando...",
                    "sLengthMenu":     "Mostrar _MENU_ registros",
                    "sZeroRecords":    "No se encontraron resultados",
                    "sEmptyTable":     "Ningún dato disponible en esta tabla",
                    "sInfo":           "Mostrando registros del _START_ al _END_ de un total de _TOTAL_ registros",
                    "sInfoEmpty":      "Mostrando registros del 0 al 0 de un total de 0 registros",
                    "sInfoFiltered":   "(filtrado de un total de _MAX_ registros)",
                    "sInfoPostFix":    "",
                    "sSearch":         "Buscar en la tabla:",
                    "sUrl":            "",
                    "sInfoThousands":  ",",
                    "sLoadingRecords": "Cargando...",
                    "oPaginate": {
                        "sFirst":    "Primero",
                        "sLast":     "Último",
                        "sNext":     "Siguiente",
                        "sPrevious": "Anterior"
                    },
                    "oAria": {
                        "sSortAscending":  ": Activar para ordenar la columna de manera ascendente",
                        "sSortDescending": ": Activar para ordenar la columna de manera descendente"
                    }
                },
                "order": [],
                "pageLength": 10
            });
        });
    </script>
</body>
</html>
"""

HTML_INDEX = HTML_BASE.replace("{% block content %}{% endblock %}", """
<div class="card shadow mb-5">
    <div class="card-header bg-dark text-white fw-bold border-bottom border-secondary">
        Control de Antena y Cobertura
    </div>
    <div class="card-body py-4">
        <form method="POST" action="/actualizar_config" class="row align-items-center">
            <div class="col-md-4">
                <div class="form-check form-switch fs-4 d-flex align-items-center">
                    <input class="form-check-input" type="checkbox" name="global_open" id="globalOpen" style="transform: scale(1.5); margin-right: 15px;" {% if global_open %}checked{% endif %}>
                    <label class="form-check-label text-white fw-bold" for="globalOpen">Señal Global Abierta</label>
                </div>
            </div>
            <div class="col-md-5">
                <label class="form-label text-muted small text-uppercase mb-0 fw-bold">Radio de Cobertura Local (Km)</label>
                <div class="d-flex align-items-center mt-2">
                    <input type="range" class="form-range flex-grow-1 me-3" name="radio_km" min="10" max="1000" step="10" value="{{ radio_km }}" id="radioRange" oninput="document.getElementById('radioVal').innerText = this.value + ' Km'">
                    <span id="radioVal" class="fw-bold text-brand fs-5">{{ radio_km }} Km</span>
                </div>
            </div>
            <div class="col-md-3 text-end">
                <button type="submit" class="btn btn-brand btn-lg px-4 fw-bold">Aplicar Directivas</button>
            </div>
        </form>
    </div>
</div>

<div class="d-flex justify-content-between align-items-center mb-3">
    <h3 class="fw-bold text-white">Gestor de Contenido VOD</h3>
    <div>
        <a href="/nuevo" class="btn btn-success me-2 fw-bold px-4">+ Nuevo Material</a>
        <a href="/sincronizar_forzado" class="btn btn-outline-info fw-bold">Forzar Sincronización</a>
    </div>
</div>
<div class="card shadow border-0 p-4 mb-5">
    <div class="table-responsive">
        <table class="table table-dark table-hover align-middle tabla-dinamica w-100">
            <thead>
                <tr>
                    <th>Estado</th>
                    <th>Miniatura</th>
                    <th>Fecha</th>
                    <th>Temática (Categoría)</th>
                    <th>Título del Material</th>
                    <th class="text-end">Acciones</th>
                </tr>
            </thead>
            <tbody>
                {% for n in noticias %}
                <tr>
                    <td class="text-center">
                        {% if n.fijado == 'true' or n.fijado == True %}
                            <span class="badge bg-danger"><i class="fw-bold">📌 Fijado</i></span>
                        {% else %}
                            <span class="badge bg-secondary">Normal</span>
                        {% endif %}
                    </td>
                    <td><img src="{{ n.imagen }}" width="80" class="rounded" style="object-fit: cover; height: 45px;" onerror="this.src='https://via.placeholder.com/80x45?text=No+Img'"></td>
                    <td class="text-muted small fw-bold" data-order="{{ n.id }}">{{ n.fecha }}</td>
                    <td><span class="text-info fw-bold">{{ n.categoria }}</span></td>
                    <td class="fw-bold">{{ n.titulo }}</td>
                    <td class="text-end">
                        <a href="/editar/{{ n.id }}" class="btn btn-sm btn-outline-light px-3 fw-bold">Editar</a>
                        <a href="/borrar/{{ n.id }}" class="btn btn-sm btn-danger px-3 ms-2 fw-bold" onclick="return confirm('ATENCIÓN: Esto borrará la noticia y sus archivos de forma permanente. ¿Proceder?')">Borrar</a>
                    </td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
</div>

<div class="d-flex justify-content-between align-items-center mb-3 mt-5">
    <h3 class="fw-bold text-white">Ciudadanos Registrados (Participación)</h3>
</div>
<div class="card shadow border-0 p-4">
    <div class="table-responsive">
        <table class="table table-dark table-hover align-middle tabla-dinamica w-100">
            <thead class="table-active">
                <tr>
                    <th>Fecha de Alta</th>
                    <th>Nombre Real</th>
                    <th>Apodo Público</th>
                    <th>WhatsApp</th>
                    <th>Código Valid.</th>
                    <th class="text-end">Seguridad</th>
                </tr>
            </thead>
            <tbody>
                {% for u in usuarios %}
                <tr>
                    <td class="text-muted small">{{ u.fecha[:10] if u.fecha else 'N/A' }}</td>
                    <td class="fw-bold text-white">{{ u.nombre_real }}</td>
                    <td class="fw-bold text-brand fs-6">{{ u.apodo }}</td>
                    <td>
                        {% if u.whatsapp != 'N/A' %}
                            <a href="https://wa.me/{{ u.whatsapp|replace('+', '')|replace(' ', '') }}" target="_blank" class="text-success fw-bold text-decoration-none">
                                🟢 {{ u.whatsapp }}
                            </a>
                        {% else %}
                            <span class="text-muted small">No registrado</span>
                        {% endif %}
                    </td>
                    <td class="text-warning fw-bold">{{ u.codigo }}</td>
                    <td class="text-end">
                        <a href="/borrar_usuario/{{ u.key }}" class="btn btn-sm btn-danger px-4 fw-bold" onclick="return confirm('ATENCIÓN: Esto expulsará al usuario, borrando su perfil de la aplicación. ¿Proceder?')">Expulsar</a>
                    </td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
</div>
""")

HTML_EDITOR = HTML_BASE.replace("{% block content %}{% endblock %}", """
<div class="card shadow border-0">
    <div class="card-header bg-success text-white fw-bold fs-5 py-3">
        {% if noticia %} Editar Material Periodístico {% else %} Creación de Nuevo Material Periodístico {% endif %}
    </div>
    <div class="card-body p-4">
        <form method="POST" action="{{ url_for('editar', id=noticia.id) if noticia else url_for('nuevo') }}" enctype="multipart/form-data">
            
            <div class="d-flex justify-content-between align-items-center border-bottom border-secondary pb-2 mb-4 mt-2">
                <h5 class="text-brand m-0">1. Información Periodística</h5>
                <div class="form-check form-switch fs-5">
                    <input class="form-check-input" type="checkbox" name="fijado" id="fijadoSwitch" {% if noticia and (noticia.fijado == 'true' or noticia.fijado == True) %}checked{% endif %}>
                    <label class="form-check-label text-warning fw-bold fs-6" for="fijadoSwitch">📌 Poner Clavito (Fijar al inicio)</label>
                </div>
            </div>
            
            <div class="row">
                <div class="col-md-8 mb-4">
                    <label class="form-label text-muted small text-uppercase fw-bold">Título del Material</label>
                    <input type="text" name="titulo" class="form-control form-control-lg fw-bold" value="{{ noticia.titulo if noticia else '' }}" placeholder="Escribe el titular aquí..." required autofocus>
                </div>
                <div class="col-md-4 mb-4">
                    <label class="form-label text-muted small text-uppercase fw-bold">Temática / Categoría</label>
                    <input type="text" name="categoria" class="form-control form-control-lg" value="{{ noticia.categoria if noticia else 'Noticias Locales' }}" required>
                </div>
            </div>
            <div class="mb-4">
                <label class="form-label text-muted small text-uppercase fw-bold">Cuerpo / Descripción del hecho</label>
                <textarea name="descripcion" class="form-control" rows="4" placeholder="Detalla la información..." required>{{ noticia.descripcion if noticia else '' }}</textarea>
            </div>

            <h5 class="text-brand border-bottom border-secondary pb-2 mb-4 mt-5">2. Archivos Multimedia (Subida Directa)</h5>
            <p class="text-muted small mb-4">Selecciona los archivos solo si deseas reemplazarlos. El sistema los subirá automáticamente a la nube R2.</p>
            
            <div class="row">
                <div class="col-md-6 mb-4">
                    <label class="form-label text-white fw-bold">Archivo de Video (MP4)</label>
                    <input type="file" name="archivo_video" accept="video/mp4,video/x-m4v,video/*" class="form-control bg-dark text-white p-3">
                    {% if noticia and noticia.videoUrl %}
                        <small class="text-info d-block mt-2">Video actual subido: {{ noticia.videoUrl.split('/')[-1] }}</small>
                    {% endif %}
                </div>
                <div class="col-md-6 mb-4">
                    <label class="form-label text-white fw-bold">Fotografía / Miniatura (JPG/PNG)</label>
                    <input type="file" name="archivo_imagen" accept="image/png, image/jpeg, image/jpg" class="form-control bg-dark text-white p-3" {% if not noticia %} required {% endif %}>
                    {% if noticia and noticia.imagen %}
                        <small class="text-info d-block mt-2">Imagen actual subida: {{ noticia.imagen.split('/')[-1] }}</small>
                    {% endif %}
                </div>
            </div>
            
            <hr class="border-secondary mt-4 mb-4">
            
            <div class="d-flex justify-content-end gap-3">
                <a href="/" class="btn btn-secondary btn-lg px-4 fw-bold">Descartar Cambios</a>
                <button type="submit" class="btn btn-success btn-lg px-5 fw-bold" onclick="this.innerHTML='Procesando... por favor espere';">
                    {% if noticia %} Actualizar Material {% else %} Subir y Publicar Noticia {% endif %}
                </button>
            </div>
        </form>
    </div>
</div>
""")

# ==========================================================
# RUTAS DEL SERVIDOR
# ==========================================================

@app.route('/')
def index():
    feed = leer_feed()
    
    global_open = False
    radio_km = 150.0
    try:
        config_ref = db.reference('admin_config').get()
        if config_ref:
            global_open = config_ref.get('global_open', False)
            radio_km = float(config_ref.get('radio_km', 150.0))
    except Exception as e:
        print(f"[ADVERTENCIA] No se pudo leer config de Firebase: {e}")

    usuarios_lista = []
    try:
        usuarios_ref = db.reference('seguridad_usuarios').get()
        if usuarios_ref:
            for key, val in usuarios_ref.items():
                usuarios_lista.append({
                    'key': key,
                    'nombre_real': val.get('nombre_real', 'No especificado'),
                    'apodo': val.get('apodo', 'Sin Apodo'),
                    'whatsapp': val.get('whatsapp', 'N/A'),
                    'codigo': val.get('codigo', 'N/A'),
                    'fecha': val.get('fecha', '')
                })
        # Ordenamos por fecha de registro (más recientes primero)
        usuarios_lista.sort(key=lambda x: x['fecha'], reverse=True)
    except Exception as e:
        print(f"[ADVERTENCIA] No se pudo leer usuarios de Firebase: {e}")

    # Forzamos un orden inicial para el panel web: Fijados primero, luego por ID (fecha)
    noticias_lista = feed.get('feed_noticias', [])
    noticias_lista.sort(key=lambda x: (x.get('fijado') == 'true' or x.get('fijado') == True), reverse=True)

    return render_template_string(HTML_INDEX, 
                                  noticias=noticias_lista,
                                  global_open=global_open,
                                  radio_km=radio_km,
                                  usuarios=usuarios_lista)

@app.route('/actualizar_config', methods=['POST'])
def actualizar_config():
    global_open = request.form.get('global_open') == 'on'
    radio_km = float(request.form.get('radio_km', 150.0))
    try:
        db.reference('admin_config').update({
            'global_open': global_open,
            'radio_km': radio_km
        })
        print(f"[FIREBASE] Políticas actualizadas -> Global: {global_open}, Radio: {radio_km}Km")
    except Exception as e:
        print(f"[ERROR FIREBASE] Falló al actualizar políticas: {e}")
        
    return redirect(url_for('index'))

@app.route('/sincronizar_forzado')
def sincronizar_forzado():
    sincronizar_json_r2()
    return redirect(url_for('index'))

@app.route('/nuevo', methods=['GET', 'POST'])
def nuevo():
    if request.method == 'POST':
        feed = leer_feed()
        nuevo_id = str(int(time.time() * 1000))
        fecha_actual = time.strftime("%d/%m/%Y")
        
        video_url = ""
        imagen_url = ""
        es_fijado = 'true' if request.form.get('fijado') == 'on' else 'false'

        if 'archivo_video' in request.files:
            video_file = request.files['archivo_video']
            if video_file and video_file.filename:
                nombre_seguro = secure_filename(f"tva_vid_{nuevo_id}_{video_file.filename}")
                s3.upload_fileobj(video_file, R2_BUCKET_NAME, nombre_seguro, ExtraArgs={'ContentType': video_file.content_type})
                video_url = f"{R2_PUBLIC_URL}/{nombre_seguro}"

        if 'archivo_imagen' in request.files:
            img_file = request.files['archivo_imagen']
            if img_file and img_file.filename:
                nombre_seguro = secure_filename(f"tva_img_{nuevo_id}_{img_file.filename}")
                s3.upload_fileobj(img_file, R2_BUCKET_NAME, nombre_seguro, ExtraArgs={'ContentType': img_file.content_type})
                imagen_url = f"{R2_PUBLIC_URL}/{nombre_seguro}"

        nueva_noticia = {
            'id': nuevo_id,
            'titulo': request.form['titulo'].strip(),
            'categoria': request.form['categoria'].strip(),
            'descripcion': request.form['descripcion'].strip(),
            'videoUrl': video_url,
            'imagen': imagen_url,
            'fecha': fecha_actual,
            'fijado': es_fijado,
            'likes': 0, 'dislikes': 0, 'sad': 0, 'happy': 0, 'vistos': 0
        }
        
        if 'feed_noticias' not in feed:
            feed['feed_noticias'] = []
            
        feed['feed_noticias'].insert(0, nueva_noticia)
        guardar_feed(feed)
        return redirect(url_for('index'))
        
    return render_template_string(HTML_EDITOR, noticia=None)

@app.route('/editar/<id>', methods=['GET', 'POST'])
def editar(id):
    feed = leer_feed()
    noticias = feed.get('feed_noticias', [])
    noticia = next((n for n in noticias if n['id'] == id), None)
    
    if not noticia:
        return redirect(url_for('index'))
        
    if request.method == 'POST':
        noticia['titulo'] = request.form['titulo'].strip()
        noticia['categoria'] = request.form['categoria'].strip()
        noticia['descripcion'] = request.form['descripcion'].strip()
        noticia['fijado'] = 'true' if request.form.get('fijado') == 'on' else 'false'

        if 'archivo_video' in request.files:
            video_file = request.files['archivo_video']
            if video_file and video_file.filename:
                nombre_seguro = secure_filename(f"tva_vid_{id}_{video_file.filename}")
                s3.upload_fileobj(video_file, R2_BUCKET_NAME, nombre_seguro, ExtraArgs={'ContentType': video_file.content_type})
                noticia['videoUrl'] = f"{R2_PUBLIC_URL}/{nombre_seguro}"

        if 'archivo_imagen' in request.files:
            img_file = request.files['archivo_imagen']
            if img_file and img_file.filename:
                nombre_seguro = secure_filename(f"tva_img_{id}_{img_file.filename}")
                s3.upload_fileobj(img_file, R2_BUCKET_NAME, nombre_seguro, ExtraArgs={'ContentType': img_file.content_type})
                noticia['imagen'] = f"{R2_PUBLIC_URL}/{nombre_seguro}"

        guardar_feed(feed)
        return redirect(url_for('index'))
        
    return render_template_string(HTML_EDITOR, noticia=noticia)

@app.route('/borrar/<id>')
def borrar(id):
    feed = leer_feed()
    noticias = feed.get('feed_noticias', [])
    noticia_a_borrar = next((n for n in noticias if n['id'] == id), None)
    
    if noticia_a_borrar:
        try:
            if noticia_a_borrar.get('videoUrl'):
                nombre_video = noticia_a_borrar['videoUrl'].split('/')[-1]
                s3.delete_object(Bucket=R2_BUCKET_NAME, Key=nombre_video)
            
            if noticia_a_borrar.get('imagen'):
                nombre_img = noticia_a_borrar['imagen'].split('/')[-1]
                s3.delete_object(Bucket=R2_BUCKET_NAME, Key=nombre_img)
        except Exception as e:
            print(f"[ERROR NUBE] Borrando archivos multimedia R2: {e}")
            
        # Borrar estadísticas y comentarios asociados en Firebase
        try:
            db.reference(f'comentarios/{id}').delete()
            db.reference(f'noticias/{id}').delete()
        except Exception as e:
            pass

        feed['feed_noticias'] = [n for n in noticias if n['id'] != id]
        guardar_feed(feed)
        
    return redirect(url_for('index'))

@app.route('/borrar_usuario/<key>')
def borrar_usuario(key):
    try:
        db.reference(f'seguridad_usuarios/{key}').delete()
        print(f"[FIREBASE] Ciudadano expulsado: {key}")
    except Exception as e:
        print(f"[ERROR FIREBASE] No se pudo borrar al usuario: {e}")
        
    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)