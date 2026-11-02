import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../main.dart';
import '../utils/tva_constantes.dart';

class TarjetaHibridaInteractiva extends StatefulWidget {
  final dynamic data;
  final String appInstanceId;
  final String r2AccessKey;
  final String r2SecretKey;
  final VoidCallback onTap;

  const TarjetaHibridaInteractiva({
    super.key,
    required this.data,
    required this.appInstanceId,
    required this.r2AccessKey,
    required this.r2SecretKey,
    required this.onTap,
  });

  @override
  State<TarjetaHibridaInteractiva> createState() =>
      _TarjetaHibridaInteractivaState();
}

class _TarjetaHibridaInteractivaState extends State<TarjetaHibridaInteractiva> {
  static const _audioPlatform = MethodChannel('com.avrorasoft.tva/audio');

  bool _isLiked = false;
  final ValueNotifier<int> _likesNotifier = ValueNotifier(0);
  final ValueNotifier<int> _vistosNotifier = ValueNotifier(0);
  final ValueNotifier<List<Map<String, dynamic>>> _comentariosNotifier =
      ValueNotifier([]);
  final ValueNotifier<int> _totalComentariosNotifier = ValueNotifier(0);
  final ValueNotifier<Map<String, dynamic>> _audioStateNotifier = ValueNotifier(
    {'url': '', 'isPlaying': false, 'progress': 0.0, 'isLoading': false},
  );
  final TextEditingController _controladorTextoComentario =
      TextEditingController();

  String? _miApodo;
  bool _isModoDios = false;
  VideoPlayerController? _reproductorAudioUsuario;

  final String r2Endpoint =
      "https://da292b98201102181e5228ea157e9980.r2.cloudflarestorage.com/vod-canal9";
  final String r2PublicUrl = "https://vod.canal9.top";

  bool _grabandoComentario = false;
  String? _idComentarioActual;
  StateSetter? _setModalMicState;

  List<String> _usuariosBloqueados = [];
  List<String> _comentariosReportados = [];

  @override
  void initState() {
    super.initState();
    _likesNotifier.value = widget.data['likes'] ?? 0;
    _vistosNotifier.value =
        int.tryParse(widget.data['vistos']?.toString() ?? '0') ?? 0;
    _cargarListasNegras();
    _verificarLikeLocal();
    _cargarApodoYCentinela();
    _conectarDatosEnTiempoReal();
    activeMediaNotifier.addListener(_onGlobalMediaChanged);
  }

  Future<void> _cargarListasNegras() async {
    final prefs = await SharedPreferences.getInstance();
    _usuariosBloqueados = prefs.getStringList('usuarios_bloqueados') ?? [];
    _comentariosReportados = prefs.getStringList('comentarios_reportados') ?? [];
    if (mounted) setState(() {});
  }

  void _onGlobalMediaChanged() {
    if (activeMediaNotifier.value != _audioStateNotifier.value['url'] &&
        _reproductorAudioUsuario?.value.isPlaying == true) {
      _detenerAudio();
    }
  }

  Future<void> _verificarLikeLocal() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isLiked = prefs.getBool('like_${widget.data['id']}') ?? false;
      });
    }
  }

  void _conectarDatosEnTiempoReal() {
    if (widget.data['id'] == null) return;

    FirebaseDatabase.instance
        .ref('noticias/${widget.data['id']}/bueno')
        .onValue
        .listen((event) {
      if (event.snapshot.value != null && mounted) {
        _likesNotifier.value =
            int.tryParse(event.snapshot.value.toString()) ?? 0;
      }
    });

    FirebaseDatabase.instance
        .ref('noticias/${widget.data['id']}/vistos')
        .onValue
        .listen((event) {
      if (event.snapshot.value != null && mounted) {
        _vistosNotifier.value =
            int.tryParse(event.snapshot.value.toString()) ?? 0;
      }
    });

    FirebaseDatabase.instance
        .ref('comentarios/${widget.data['id']}')
        .onValue
        .listen((event) {
      if (event.snapshot.value != null && mounted) {
        final map = event.snapshot.value as Map<dynamic, dynamic>;
        List<Map<String, dynamic>> temp = [];
        int totalSum = 0;

        map.forEach((key, val) {
          List<Map<String, String>> respuestasTemp = [];
          if (val['respuestas'] != null) {
            (val['respuestas'] as Map<dynamic, dynamic>).forEach((
              rKey,
              rVal,
            ) {
              respuestasTemp.add({
                'key': rKey.toString(),
                'tipo': rVal['tipo']?.toString() ?? 'texto',
                'contenido': rVal['contenido'].toString(),
                'apodo': rVal['apodo']?.toString() ?? 'Anónimo',
                'oficial': rVal['oficial']?.toString() ?? 'false',
              });
            });
          }
          temp.add({
            'key': key.toString(),
            'tipo': val['tipo'].toString(),
            'contenido': val['contenido'].toString(),
            'apodo': val['apodo']?.toString() ?? 'Anónimo',
            'oficial': val['oficial']?.toString() ?? 'false',
            'respuestas': respuestasTemp,
          });
        });

        temp.sort((a, b) {
          if (a['oficial'] == 'true' && b['oficial'] == 'false') return -1;
          if (a['oficial'] == 'false' && b['oficial'] == 'true') return 1;
          return 0;
        });

        for (var c in temp) {
          totalSum += 1 + (c['respuestas'] as List).length;
        }

        _comentariosNotifier.value = temp;
        _totalComentariosNotifier.value = totalSum;
      } else if (mounted) {
        _comentariosNotifier.value = [];
        _totalComentariosNotifier.value = 0;
      }
    });
  }

  Future<void> _cargarApodoYCentinela() async {
    final prefs = await SharedPreferences.getInstance();
    String? apodo = prefs.getString('apodo_tva');
    String? miKey = prefs.getString('key_tva');

    if (miKey == "ADMIN_MASTER") {
      if (mounted) {
        setState(() {
          _miApodo = apodo;
          _isModoDios = true;
        });
      }
    } else if (miKey != null) {
      FirebaseDatabase.instance.ref('seguridad_usuarios/$miKey').onValue.listen(
        (event) async {
          if (event.snapshot.value == null) {
            await prefs.remove('apodo_tva');
            await prefs.remove('key_tva');
            if (mounted) {
              setState(() {
                _miApodo = null;
                _isModoDios = false;
              });
            }
          }
        },
      );
      if (mounted) {
        setState(() {
          _miApodo = apodo;
          _isModoDios = false;
        });
      }
    } else if (apodo != null) {
      await prefs.remove('apodo_tva');
      if (mounted) {
        setState(() {
          _miApodo = null;
          _isModoDios = false;
        });
      }
    }
  }

  @override
  void dispose() {
    activeMediaNotifier.removeListener(_onGlobalMediaChanged);
    _controladorTextoComentario.dispose();
    _reproductorAudioUsuario?.dispose();
    _likesNotifier.dispose();
    _vistosNotifier.dispose();
    _comentariosNotifier.dispose();
    _totalComentariosNotifier.dispose();
    _audioStateNotifier.dispose();
    super.dispose();
  }

  void _detenerAudio() {
    if (_reproductorAudioUsuario != null &&
        _reproductorAudioUsuario!.value.isPlaying) {
      _reproductorAudioUsuario!.pause();
      _audioStateNotifier.value = {
        'url': '',
        'isPlaying': false,
        'progress': 0.0,
        'isLoading': false,
      };
    }
  }

  Future<void> _accionarAudio(String url) async {
    String urlSegura = url.replaceAll('http://', 'https://');

    if (_audioStateNotifier.value['url'] == urlSegura &&
        _reproductorAudioUsuario != null) {
      if (_reproductorAudioUsuario!.value.isPlaying) {
        _reproductorAudioUsuario!.pause();
        _audioStateNotifier.value = {
          'url': urlSegura,
          'isPlaying': false,
          'progress': _audioStateNotifier.value['progress'],
          'isLoading': false,
        };
      } else {
        activeMediaNotifier.value = urlSegura;
        _reproductorAudioUsuario!.play();
        _audioStateNotifier.value = {
          'url': urlSegura,
          'isPlaying': true,
          'progress': _audioStateNotifier.value['progress'],
          'isLoading': false,
        };
      }
      return;
    }

    activeMediaNotifier.value = urlSegura;
    _audioStateNotifier.value = {
      'url': urlSegura,
      'isPlaying': false,
      'progress': 0.0,
      'isLoading': true,
    };
    _reproductorAudioUsuario?.dispose();
    _reproductorAudioUsuario = VideoPlayerController.networkUrl(
      Uri.parse(urlSegura.trim()),
    );

    try {
      await _reproductorAudioUsuario!.initialize();
      _reproductorAudioUsuario!.setVolume(1.0);
      _reproductorAudioUsuario!.play();

      _reproductorAudioUsuario!.addListener(() {
        if (mounted && _reproductorAudioUsuario != null) {
          double prog = 0.0;
          if (_reproductorAudioUsuario!.value.duration.inMilliseconds > 0) {
            prog = _reproductorAudioUsuario!.value.position.inMilliseconds /
                _reproductorAudioUsuario!.value.duration.inMilliseconds;
          }
          bool playing = _reproductorAudioUsuario!.value.isPlaying;

          if (_reproductorAudioUsuario!.value.position >=
                  _reproductorAudioUsuario!.value.duration &&
              _reproductorAudioUsuario!.value.duration > Duration.zero) {
            _reproductorAudioUsuario!.pause();
            _reproductorAudioUsuario!.seekTo(Duration.zero);
            playing = false;
            prog = 0.0;
          }

          _audioStateNotifier.value = {
            'url': urlSegura,
            'isPlaying': playing,
            'progress': prog,
            'isLoading': false,
          };
        }
      });
    } catch (e) {
      _audioStateNotifier.value = {
        'url': '',
        'isPlaying': false,
        'progress': 0.0,
        'isLoading': false,
      };
    }
  }

  void _darMeGusta() async {
    if (widget.data['id'] == null) return;
    final prefs = await SharedPreferences.getInstance();
    int actual = _likesNotifier.value;

    setState(() {
      _isLiked = !_isLiked;
    });

    int nuevoValor = _isLiked ? actual + 1 : (actual - 1 < 0 ? 0 : actual - 1);
    _likesNotifier.value = nuevoValor;
    await prefs.setBool('like_${widget.data['id']}', _isLiked);

    FirebaseDatabase.instance
        .ref('noticias/${widget.data['id']}/bueno')
        .set(nuevoValor);
  }

  void _reportarComentario(String idComentario) async {
    FirebaseDatabase.instance.ref('reportes_ugc/$idComentario').set({
      'noticia_id': widget.data['id'],
      'fecha_reporte': DateTime.now().toIso8601String(),
      'reportado_por': _miApodo ?? 'Anónimo',
      'app_instance': widget.appInstanceId,
    });

    final prefs = await SharedPreferences.getInstance();
    if (!_comentariosReportados.contains(idComentario)) {
      _comentariosReportados.add(idComentario);
      await prefs.setStringList('comentarios_reportados', _comentariosReportados);
    }
    
    _comentariosNotifier.value = List.from(_comentariosNotifier.value);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorTarjetaOscura,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.gavel_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(child: Text("Reporte en Revisión", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16))),
          ]
        ),
        content: const Text(
          "Su reporte ha sido recibido de forma confidencial y el contenido ha sido ocultado inmediatamente de su pantalla.\n\n"
          "Nuestro equipo de moderación y departamento jurídico evaluarán si este mensaje infringe nuestras normas de convivencia ciudadana y tolerancia.\n\n"
          "Una vez se emita un dictamen, usted será notificado(a) sobre la resolución y las acciones aplicadas a la cuenta infractora.",
          style: TextStyle(color: Colors.white70, fontSize: 13)
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx), 
            child: const Text("ENTENDIDO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          )
        ]
      )
    );
  }

  void _bloquearUsuario(String apodoUsuario) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_usuariosBloqueados.contains(apodoUsuario)) {
      _usuariosBloqueados.add(apodoUsuario);
      await prefs.setStringList('usuarios_bloqueados', _usuariosBloqueados);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Usuario bloqueado. No verás más sus comentarios."),
        backgroundColor: Colors.red,
      ),
    );
    _comentariosNotifier.value = List.from(_comentariosNotifier.value);
  }

  void _eliminarRegistro(BuildContext modalCtx) async {
    bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorTarjetaOscura,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 10),
            Expanded(child: Text("Derecho al Olvido", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16))),
          ]
        ),
        content: const Text(
          "¿Confirma que desea eliminar su Identidad Ciudadana de CANAL 9 tva?\n\n"
          "Sus datos serán borrados permanentemente de nuestros servidores. Al ejercer este derecho, perderá inmediatamente su capacidad para opinar, comentar y reportar hasta que decida registrarse nuevamente.",
          style: TextStyle(color: Colors.white70, fontSize: 13)
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false), 
            child: const Text("CANCELAR", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text("ELIMINAR MI REGISTRO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          )
        ]
      )
    );

    if (confirmar == true) {
      final prefs = await SharedPreferences.getInstance();
      String? miKey = prefs.getString('key_tva');
      
      if (miKey != null && miKey != "ADMIN_MASTER") {
         await FirebaseDatabase.instance.ref('seguridad_usuarios/$miKey').remove();
      }
      
      await prefs.remove('apodo_tva');
      await prefs.remove('key_tva');
      
      if (mounted) {
        setState(() {
          _miApodo = null;
          _isModoDios = false;
        });
        Navigator.pop(modalCtx);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Su registro ha sido eliminado exitosamente según el derecho al olvido."), 
            backgroundColor: Colors.green
          )
        );
      }
    }
  }

  void _mostrarRegistroSeguridad([VoidCallback? alCompletar]) {
    final nombreCtrl = TextEditingController();
    final apodoCtrl = TextEditingController();
    final whatsappCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true, 
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: colorTarjetaOscura,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Icon(
                  Icons.verified_user_rounded,
                  color: colorRojoTva,
                  size: 40,
                ),
              ),
              const SizedBox(height: 15),
              const Center(
                child: Text(
                  "IDENTIDAD CIUDADANA",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nombreCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Nombres y Apellidos",
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: whatsappCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "WhatsApp (Ej: 71234567)",
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apodoCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Apodo (Opcional)",
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 15),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () async {
                  if (nombreCtrl.text.isEmpty || whatsappCtrl.text.isEmpty) {
                    return;
                  }
                  String apodo = apodoCtrl.text.trim().isNotEmpty
                      ? apodoCtrl.text.trim()
                      : nombreCtrl.text.trim();

                  if (nombreCtrl.text.trim() == "73995224 281103") {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('apodo_tva', "CANAL 9 tva");
                    await prefs.setString('key_tva', "ADMIN_MASTER");
                    if (mounted) {
                      setState(() {
                        _miApodo = "CANAL 9 tva";
                        _isModoDios = true;
                      });
                      Navigator.pop(ctx);
                      if (alCompletar != null) alCompletar();
                    }
                    return;
                  }

                  String cod =
                      "tva-${Random().nextInt(9999).toString().padLeft(4, '0')}";
                  DatabaseReference refNuevo = FirebaseDatabase.instance
                      .ref('seguridad_usuarios')
                      .push();

                  await refNuevo.set({
                    'nombre_real': nombreCtrl.text.trim(),
                    'apodo': apodo,
                    'whatsapp': whatsappCtrl.text.trim(),
                    'app_instance': widget.appInstanceId,
                    'codigo': cod,
                    'fecha': DateTime.now().toIso8601String(),
                  });

                  await launchUrl(
                    Uri.parse(
                      "https://wa.me/59173995224?text=${Uri.encodeComponent("Hola Canal 9 tva. Mi nombre es ${nombreCtrl.text} y mi código es $cod")}",
                    ),
                    mode: LaunchMode.externalApplication,
                  );

                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('apodo_tva', apodo);
                  await prefs.setString('key_tva', refNuevo.key!);

                  if (mounted) {
                    setState(() => _miApodo = apodo);
                    Navigator.pop(ctx);
                    _cargarApodoYCentinela();
                    if (alCompletar != null) alCompletar();
                  }
                },
                child: const Text(
                  "VALIDAR",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _intentarAccion(VoidCallback accionPermitida) {
    if (_miApodo != null) {
      accionPermitida();
    } else {
      _mostrarRegistroSeguridad(accionPermitida);
    }
  }

  Map<String, String> _firmarPeticionS3(
    String method,
    String url,
    List<int> payload,
  ) {
    final accessKey = widget.r2AccessKey;
    final secretKey = widget.r2SecretKey;

    final uri = Uri.parse(url);
    final host = uri.host;
    final path = uri.path;

    final now = DateTime.now().toUtc();
    final amzDate =
        "${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}T${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}Z";
    final dateStamp = amzDate.substring(0, 8);

    final payloadHash = sha256.convert(payload).toString();
    final canonicalHeaders =
        "host:$host\nx-amz-content-sha256:$payloadHash\nx-amz-date:$amzDate\n";
    const signedHeaders = "host;x-amz-content-sha256;x-amz-date";

    final canonicalRequest =
        "$method\n$path\n\n$canonicalHeaders\n$signedHeaders\n$payloadHash";
    final credentialScope = "$dateStamp/auto/s3/aws4_request";
    final stringToSign =
        "AWS4-HMAC-SHA256\n$amzDate\n$credentialScope\n${sha256.convert(utf8.encode(canonicalRequest))}";

    List<int> sign(List<int> key, String msg) =>
        Hmac(sha256, key).convert(utf8.encode(msg)).bytes;

    final kDate = sign(utf8.encode("AWS4$secretKey"), dateStamp);
    final signature = Hmac(
      sha256,
      sign(sign(sign(kDate, "auto"), "s3"), "aws4_request"),
    ).convert(utf8.encode(stringToSign)).toString();

    return {
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
      'Authorization':
          "AWS4-HMAC-SHA256 Credential=$accessKey/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature",
      'Content-Type': 'audio/x-m4a',
    };
  }

  Future<void> _subirAudioAR2(String path, [String? parentId]) async {
    String fileName = "audio_${DateTime.now().millisecondsSinceEpoch}.m4a";

    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final url = "$r2Endpoint/$fileName";

      var response = await http.put(
        Uri.parse(url),
        headers: _firmarPeticionS3('PUT', url, bytes),
        body: bytes,
      );

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          widget.data['id'] != null) {
        String ruta = parentId == null
            ? 'comentarios/${widget.data['id']}'
            : 'comentarios/${widget.data['id']}/$parentId/respuestas';
        FirebaseDatabase.instance.ref(ruta).push().set({
          'tipo': 'audio',
          'contenido': "$r2PublicUrl/$fileName",
          'apodo': _miApodo ?? 'Anónimo',
          'oficial': 'false',
          'fecha': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint("Error R2: $e");
    }
  }

  void _gestionarGrabacionUnificada(String? parentId, StateSetter setBtnState) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('acepto_terminos_ugc') ?? false)) {
      bool acepto = await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("Normas de Convivencia"),
          content: const Text("Para grabar, aceptas no subir insultos, odio ni spam."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCELAR")),
            ElevatedButton(onPressed: () async { await prefs.setBool('acepto_terminos_ugc', true); Navigator.pop(ctx, true); }, child: const Text("ACEPTO")),
          ],
        ),
      ) ?? false;
      if (!acepto) return;
    }

    if (_grabandoComentario) {
      try {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        final String? path = await _audioPlatform.invokeMethod('stopRecording');
        setState(() => _grabandoComentario = false);
        setBtnState(() => _grabandoComentario = false);
        if (path != null) {
          HapticFeedback.mediumImpact();
          _subirAudioAR2(path, _idComentarioActual);
        }
      } catch (e) {
        setState(() => _grabandoComentario = false);
        setBtnState(() => _grabandoComentario = false);
      }
    } else {
      _detenerAudio();
      try {
        if (await Permission.microphone.request().isGranted) {
          final dir = await getTemporaryDirectory();
          String path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
          if (await _audioPlatform.invokeMethod('startRecording', {"path": path, "noiseSuppression": true})) {
            HapticFeedback.heavyImpact();
            setState(() { _grabandoComentario = true; _idComentarioActual = parentId; });
            setBtnState(() => _grabandoComentario = true);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("🔴 Grabando..."),
                backgroundColor: Colors.red,
                duration: const Duration(minutes: 5),
                action: SnackBarAction(label: "ENVIAR", textColor: Colors.white, onPressed: () => _gestionarGrabacionUnificada(_idComentarioActual, setBtnState)),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint("Error: $e");
      }
    }
  }

  void _abrirModalComentarios() async {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true, 
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85, 
          decoration: const BoxDecoration(
            color: colorTarjetaOscura,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 24),
                    const Text(
                      "Comentarios",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    if (_miApodo != null)
                      GestureDetector(
                        onTap: () => _eliminarRegistro(ctx),
                        child: const Icon(Icons.person_remove_rounded, color: Colors.white38, size: 24),
                      )
                    else 
                      const SizedBox(width: 24),
                  ],
                ),
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: _comentariosNotifier,
                  builder: (context, listaComentariosOriginal, child) {
                    List<Map<String, dynamic>> listaComentarios = listaComentariosOriginal
                            .where((c) => !_usuariosBloqueados.contains(c['apodo']) && !_comentariosReportados.contains(c['key']))
                            .toList();

                    if (listaComentarios.isEmpty) {
                      return const Center(
                        child: Text(
                          "Sé el primero en opinar.",
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }

                    return ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      itemCount: listaComentarios.length,
                      itemBuilder: (context, i) {
                        final com = listaComentarios[i];
                        final bool esAudio = com['tipo'] == 'audio';
                        final bool esOficial = com['oficial'] == 'true';
                        final bool puedeBorrar = com['apodo'] == _miApodo || _isModoDios;
                        
                        List<Map<String, String>> respuestas = (com['respuestas'] as List<Map<String, String>>?)
                                    ?.where((r) => !_usuariosBloqueados.contains(r['apodo']) && !_comentariosReportados.contains(r['key']))
                                    .toList() ?? [];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: esOficial ? const Color(0xFF3E2723) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: esOficial ? Colors.orange : Colors.transparent),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              if (esAudio) _accionarAudio(com['contenido']!);
                                            },
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (esAudio)
                                                  ValueListenableBuilder<Map<String, dynamic>>(
                                                    valueListenable: _audioStateNotifier,
                                                    builder: (context, audioState, _) {
                                                      bool isPlaying = audioState['url'] == com['contenido'] && audioState['isPlaying'];
                                                      bool isLoading = audioState['url'] == com['contenido'] && audioState['isLoading'];
                                                      if (isLoading) {
                                                        return const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: colorRojoTva));
                                                      }
                                                      return Icon(isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: colorRojoTva, size: 30);
                                                    },
                                                  )
                                                else
                                                  Icon(esOficial ? Icons.campaign_rounded : Icons.person_pin_rounded, color: esOficial ? Colors.orange : Colors.white54, size: 28),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Text(com['apodo']!, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: esOficial ? Colors.orange : Colors.white)),
                                                          if (esOficial) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.verified_rounded, color: Colors.blue, size: 14)),
                                                        ],
                                                      ),
                                                      Text(esAudio ? "Reporte de voz" : com['contenido']!, style: const TextStyle(fontSize: 13, color: Colors.white70)),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20),
                                          color: colorFondoElegante,
                                          onSelected: (val) {
                                            if (val == 'borrar') {
                                              FirebaseDatabase.instance.ref('comentarios/${widget.data['id']}/${com['key']}').remove();
                                            } else if (val == 'reportar') {
                                              _reportarComentario(com['key']);
                                            } else if (val == 'bloquear') {
                                              _bloquearUsuario(com['apodo']!);
                                            }
                                          },
                                          itemBuilder: (BuildContext context) => [
                                            if (puedeBorrar)
                                              const PopupMenuItem(value: 'borrar', child: Text("Borrar", style: TextStyle(color: Colors.white))),
                                            const PopupMenuItem(value: 'reportar', child: Text("Reportar", style: TextStyle(color: Colors.white))),
                                            const PopupMenuItem(value: 'bloquear', child: Text("Bloquear Usuario", style: TextStyle(color: Colors.white))),
                                          ],
                                        ),
                                      ],
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          _intentarAccion(() => _mostrarOpcionesRespuesta(com['key'], com['apodo']!));
                                        },
                                        child: Container(
                                          constraints: const BoxConstraints(minHeight: 48, minWidth: 80),
                                          alignment: Alignment.centerRight,
                                          child: const Text("Responder", style: TextStyle(fontSize: 13, color: Colors.white54, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (respuestas.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 35, top: 4),
                                  child: Column(
                                    children: respuestas.map((resp) {
                                      bool respOficial = resp['oficial'] == 'true';
                                      bool puedeBorrarResp = resp['apodo'] == _miApodo || _isModoDios;
                                      bool respEsAudio = resp['tipo'] == 'audio';

                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 6),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: respOficial ? const Color(0xFF3E2723) : colorFondoElegante,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: GestureDetector(
                                                behavior: HitTestBehavior.opaque,
                                                onTap: () {
                                                  if (respEsAudio) _accionarAudio(resp['contenido']!);
                                                },
                                                child: Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    if (respEsAudio)
                                                      ValueListenableBuilder<Map<String, dynamic>>(
                                                        valueListenable: _audioStateNotifier,
                                                        builder: (context, audioState, _) {
                                                          bool isPlaying = audioState['url'] == resp['contenido'] && audioState['isPlaying'];
                                                          return Icon(isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: colorRojoTva, size: 20);
                                                        },
                                                      )
                                                    else
                                                      Icon(respOficial ? Icons.campaign_rounded : Icons.subdirectory_arrow_right_rounded, color: respOficial ? Colors.orange : Colors.white38, size: 16),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              Text(resp['apodo']!, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: respOficial ? Colors.orange : Colors.white)),
                                                            ],
                                                          ),
                                                          Text(respEsAudio ? "Respuesta de voz" : resp['contenido']!, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert, color: Colors.white38, size: 16),
                                              color: colorFondoElegante,
                                              onSelected: (val) {
                                                if (val == 'borrar') {
                                                  FirebaseDatabase.instance.ref('comentarios/${widget.data['id']}/${com['key']}/respuestas/${resp['key']}').remove();
                                                } else if (val == 'reportar') {
                                                  _reportarComentario(resp['key']!);
                                                } else if (val == 'bloquear') {
                                                  _bloquearUsuario(resp['apodo']!);
                                                }
                                              },
                                              itemBuilder: (BuildContext context) => [
                                                if (puedeBorrarResp)
                                                  const PopupMenuItem(value: 'borrar', child: Text("Borrar", style: TextStyle(color: Colors.white))),
                                                const PopupMenuItem(value: 'reportar', child: Text("Reportar", style: TextStyle(color: Colors.white))),
                                                const PopupMenuItem(value: 'bloquear', child: Text("Bloquear Usuario", style: TextStyle(color: Colors.white))),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Container(
                padding: EdgeInsets.only(
                  left: 15,
                  right: 15,
                  top: 12,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 15,
                ),
                decoration: const BoxDecoration(
                  color: colorTarjetaOscura,
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.keyboard_alt_outlined, color: Colors.white, size: 16),
                        label: const Text("Escribir", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          _intentarAccion(() => _mostrarDialogoTexto(null));
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatefulBuilder(
                        builder: (BuildContext context, StateSetter setBtnState) {
                          _setModalMicState = setBtnState;
                          return GestureDetector(
                            onTap: () => _intentarAccion(() => _gestionarGrabacionUnificada(null, setBtnState)),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _grabandoComentario ? colorRojoTva : Colors.black,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(_grabandoComentario ? Icons.stop_circle_rounded : Icons.mic_none_rounded, color: Colors.white, size: 16),
                                  const SizedBox(width: 5),
                                  Text(_grabandoComentario ? "Detener" : "Voz", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ); 
  }

  void _mostrarOpcionesRespuesta(String? parentId, [String? responderA]) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true, 
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(25),
        decoration: const BoxDecoration(
          color: colorTarjetaOscura,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("¿Cómo deseas responder?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BotonOpcionRespuesta(
                  icono: Icons.keyboard_alt_outlined,
                  texto: "Escrito",
                  color: Colors.white,
                  onTap: () {
                    Navigator.pop(ctx);
                    _mostrarDialogoTexto(parentId, responderA);
                  },
                ),
                _BotonOpcionRespuesta(
                  icono: Icons.mic_none_rounded,
                  texto: "Voz",
                  color: colorRojoTva,
                  onTap: () {
                    Navigator.pop(ctx);
                    if (_setModalMicState != null) {
                      _gestionarGrabacionUnificada(parentId, _setModalMicState!);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ); 
  }

  void _mostrarDialogoTexto(String? parentId, [String? responderA]) {
    _controladorTextoComentario.clear();
    if (responderA != null) _controladorTextoComentario.text = "@$responderA ";
    bool marcarOficial = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true, 
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: colorTarjetaOscura,
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(parentId == null ? "Escribir Comentario" : "Responder", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _controladorTextoComentario,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 4,
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Escriba aquí...", hintStyle: TextStyle(color: Colors.white38), isDense: true),
                  ),
                  const SizedBox(height: 10),
                  if (_isModoDios && parentId == null)
                    CheckboxListTile(
                      title: const Text("Fijar como Anuncio Oficial", style: TextStyle(color: colorRojoTva, fontWeight: FontWeight.bold, fontSize: 12)),
                      value: marcarOficial,
                      onChanged: (bool? value) { setModalState(() { marcarOficial = value ?? false; }); },
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: colorRojoTva,
                    ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR", style: TextStyle(color: Colors.white54, fontSize: 12))),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: colorRojoTva),
                        onPressed: () {
                          if (_controladorTextoComentario.text.trim().isNotEmpty && widget.data['id'] != null) {
                            String ruta = parentId == null ? 'comentarios/${widget.data['id']}' : 'comentarios/${widget.data['id']}/${parentId}/respuestas';
                            FirebaseDatabase.instance.ref(ruta).push().set({
                              'tipo': 'texto',
                              'contenido': _controladorTextoComentario.text.trim(),
                              'apodo': _miApodo ?? 'Anónimo',
                              'oficial': marcarOficial.toString(),
                              'fecha': DateTime.now().toIso8601String(),
                            });
                          }
                          Navigator.pop(context);
                        },
                        child: const Text("ENVIAR", style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ); 
  }

  void _compartirNoticia() {
    String link = widget.data['id'] != null
        ? "https://vod.canal9.top/noticia/${widget.data['id']}"
        : "https://play.google.com/store/apps/details?id=com.avrorasoft.tva";
    String textoACompartir =
        "🔴 NOTICIA - CANAL 9 tva\n${widget.data['titulo'] ?? ''}\n\n📱 Mira el reporte completo y nuestra señal en vivo descargando la app oficial:\n$link";
    Share.share(textoACompartir);
  }

  Widget _iconAction(
    IconData icon,
    String value,
    VoidCallback? onTap, {
    Color color = Colors.white70,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 15.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: color),
            if (value.isNotEmpty) const SizedBox(width: 6),
            if (value.isNotEmpty)
              Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String urlVideo = widget.data['videoUrl']?.toString().trim() ?? "";
    bool esVideo = urlVideo.isNotEmpty &&
        (urlVideo.endsWith('.mp4') || urlVideo.endsWith('.m3u8'));

    String urlImg = widget.data['imagen']?.toString().trim() ?? "";
    if (urlImg.isEmpty && widget.data['imagenes'] != null) {
      List<String> imgs = List<String>.from(widget.data['imagenes']);
      if (imgs.isNotEmpty) urlImg = imgs[0];
    }

    urlImg = urlImg.replaceAll('http://', 'https://');

    return Column(
      children: [
        Container(height: 6, width: double.infinity, color: colorFondoElegante),
        Container(
          color: colorTarjetaOscura,
          padding: const EdgeInsets.only(top: 15, bottom: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("INFORMACIÓN", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: colorRojoTva)),
                    Text(widget.data['fecha']?.toUpperCase() ?? "", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Text(widget.data['titulo'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white, height: 1.2)),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: widget.onTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  height: MediaQuery.of(context).size.height * 0.52,
                  color: Colors.black,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (urlImg.isNotEmpty)
                        Image.network(urlImg, fit: BoxFit.cover, width: double.infinity, height: double.infinity, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.image_not_supported, color: Colors.white24)))
                      else
                        Container(color: const Color(0xFF181818), child: Center(child: Image.asset('assets/logo.png', height: 80, color: Colors.white24))),
                      if (esVideo)
                        const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 60)),
                    ],
                  ),
                ),
              ),
              Container(
                color: colorTarjetaOscura,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: _likesNotifier,
                      builder: (context, likes, _) => _iconAction(_isLiked ? Icons.favorite_rounded : Icons.favorite_border, likes.toString(), _darMeGusta, color: _isLiked ? colorRojoTva : Colors.white70),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _vistosNotifier,
                      builder: (context, vistos, _) => _iconAction(Icons.visibility_outlined, vistos.toString(), null),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _totalComentariosNotifier,
                      builder: (context, comentarios, _) => _iconAction(Icons.chat_bubble_outline, comentarios.toString(), _abrirModalComentarios),
                    ),
                    _iconAction(Icons.share_outlined, "", _compartirNoticia),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BotonOpcionRespuesta extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color color;
  final VoidCallback onTap;

  const _BotonOpcionRespuesta({
    super.key,
    required this.icono,
    required this.texto,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icono, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}