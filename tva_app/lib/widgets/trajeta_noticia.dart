import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chewie/chewie.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'noticia_detalle_screen.dart';
import 'utils/tva_constantes.dart'; // Si aquí tienes colores viejos, los sobreescribimos abajo
import 'widgets/tarjeta_noticia.dart';

// ==========================================
// CONSTANTES GLOBALES INYECTADAS
// ==========================================
const Color colorVerdeTva = Color(0xFF006F25); // El nuevo Verde Amazonía
// Asumimos que tienes estas dos en tus constantes, si no, se usan por defecto:
const Color colorFondoElegante = Color(0xFF121212);
const Color colorTarjetaOscura = Color(0xFF1E1E1E);

final GlobalKey<NavigatorState> llavedeNavegacionGlobal = GlobalKey<NavigatorState>();
final ValueNotifier<String> activeMediaNotifier = ValueNotifier("");

// ==========================================
// SERVICIO: ESTABILIZADOR DE AUDIO GLOBAL
// ==========================================
class ServicioNormalizadorAudio {
  static final ServicioNormalizadorAudio _instancia = ServicioNormalizadorAudio._interno();
  factory ServicioNormalizadorAudio() => _instancia;
  ServicioNormalizadorAudio._interno();

  void normalizarVolumen(VideoPlayerController controlador) {
    // Fija el volumen a un 85% para normalizar picos altos y levantar audios bajos
    controlador.setVolume(0.85);
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inmersión absoluta desde el milisegundo cero
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const Canal9tva());
}

class Canal9tva extends StatelessWidget {
  const Canal9tva({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CANAL 9 tva',
      navigatorKey: llavedeNavegacionGlobal,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: colorVerdeTva, // Cambiado al verde Amazonía
        scaffoldBackgroundColor: colorFondoElegante,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const RootController(),
    );
  }
}

class _BotonOpcionRespuesta extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color color;
  final VoidCallback onTap;

  const _BotonOpcionRespuesta({
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
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icono, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          Text(
            texto,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class RootController extends StatefulWidget {
  const RootController({super.key});

  @override
  State<RootController> createState() => _RootControllerState();
}

class _RootControllerState extends State<RootController> {
  final String streamUrl = "https://envivo.canal9.top/live/tv/index.m3u8";
  final String feedJsonUrl = "https://vod.canal9.top/noticias.json";
  final String accessControlUrl = "https://vod.canal9.top/access_control.json";
  static const _linkChannel = MethodChannel('com.avrorasoft.tva/deeplink');

  String r2AccessKey = "";
  String r2SecretKey = "";

  final double baseLat = -11.0065;
  final double baseLng = -66.0631;
  double radioKm = 150.0;
  bool salidaGlobal = false;
  String idHardware = "";
  List<dynamic> materialesFeed = [];
  bool analizando = true;
  bool autorizado = false;
  String logSeguridad = "";
  bool zonaPermitida = true;

  @override
  void initState() {
    super.initState();
    _suscribirEventosPush();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ejecutarProtocoloMaestro(),
    );
    _configurarOyenteDeepLinks();
  }

  void _suscribirEventosPush() async {
    await FirebaseMessaging.instance.subscribeToTopic('tva_noticias');
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['accion'] == 'forzar_actualizacion') {
        _sincronizarFeedSilencioso();
      } else if (message.data['accion'] == 'forzar_reinicio_seguridad') {
        _ejecutarProtocoloMaestro();
      }
    });
  }

  Future<void> _sincronizarFeedSilencioso() async {
    if (feedJsonUrl.isEmpty) return;
    try {
      final resFeed = await http.get(
        Uri.parse("$feedJsonUrl?t=${DateTime.now().millisecondsSinceEpoch}"),
      );
      if (resFeed.statusCode == 200) {
        final nuevosMateriales =
            json.decode(resFeed.body)['feed_noticias'] ?? [];
        if (mounted) {
          setState(() {
            materialesFeed = nuevosMateriales;
          });
        }
      }
    } catch (e) {
      debugPrint("Error en sincronización reactiva: $e");
    }
  }

  void _configurarOyenteDeepLinks() async {
    try {
      final String? linkInicial = await _linkChannel.invokeMethod('getInitialLink');
      if (linkInicial != null) {
        _procesarUrlDeepLink(linkInicial);
      }
    } catch (e) {
      debugPrint("Error al recibir enlace inicial: $e");
    }

    _linkChannel.setMethodCallHandler((call) async {
      if (call.method == "onLinkReceived") {
        final String? link = call.arguments as String?;
        if (link != null) {
          _procesarUrlDeepLink(link);
        }
      }
    });
  }

  void _procesarUrlDeepLink(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.contains('noticia')) {
        final idx = uri.pathSegments.indexOf('noticia');
        if (idx + 1 < uri.pathSegments.length) {
          final idNoticia = uri.pathSegments[idx + 1];
          _redireccionarANoticiaDirecta(idNoticia);
        }
      }
    } catch (e) {
      debugPrint("Error al procesar URL: $e");
    }
  }

  void _redireccionarANoticiaDirecta(String idNoticia) async {
    final snapshot =
        await FirebaseDatabase.instance.ref('noticias/$idNoticia').get();

    if (snapshot.exists) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      final urlVideo = data['videoUrl']?.toString() ?? "";

      if (urlVideo.isNotEmpty) {
        FirebaseDatabase.instance
            .ref('noticias/$idNoticia/vistos')
            .runTransaction((Object? v) {
          if (v == null) return Transaction.success(1);
          return Transaction.success((v as int) + 1);
        });
        activeMediaNotifier.value = urlVideo;
        llavedeNavegacionGlobal.currentState?.push(
          MaterialPageRoute(
            builder: (c) => ReproductorVODForzado(urlVideo: urlVideo),
          ),
        );
      }
    }
  }

  Future<bool> _mostrarDivulgacionUbicacion() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: colorTarjetaOscura,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Row(
              children: [
                Icon(Icons.location_on_rounded, color: colorVerdeTva), // Verde
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Uso de Ubicación",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            content: const Text(
              "Canal 9 tva recopila datos de ubicación para habilitar la transmisión en vivo únicamente cuando la aplicación está en uso. Esto es necesario para garantizar que el contenido se visualice exclusivamente dentro de las zonas geográficas autorizadas por derechos de transmisión.",
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  "DENEGAR",
                  style: TextStyle(
                    color: Colors.white54,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: colorVerdeTva), // Verde
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "ACEPTAR",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _ejecutarProtocoloMaestro() async {
    setState(() {
      analizando = true;
      logSeguridad = "";
      zonaPermitida = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      idHardware = prefs.getString('app_instance_id') ?? "";
      if (idHardware.isEmpty) {
        idHardware = "app_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}";
        await prefs.setString('app_instance_id', idHardware);
      }

      try {
        final secureSnapshot = await FirebaseDatabase.instance
            .ref('secure_config')
            .get()
            .timeout(const Duration(seconds: 10));
        if (secureSnapshot.exists) {
          final secureData = secureSnapshot.value as Map<dynamic, dynamic>;
          r2AccessKey = secureData['r2_access_key'] ?? "";
          r2SecretKey = secureData['r2_secret_key'] ?? "";
        }
      } catch (e) {
        debugPrint("Fallo al obtener llaves: $e");
      }

      final resAccess = await http
          .get(Uri.parse("$accessControlUrl?t=${DateTime.now().millisecondsSinceEpoch}"))
          .timeout(const Duration(seconds: 10));

      if (resAccess.statusCode == 200) {
        final accessData = json.decode(resAccess.body);
        salidaGlobal = accessData['global_open'] ?? false;
        radioKm = (accessData['radio_km'] ?? 150.0).toDouble();

        if ((accessData['banned_ids'] ?? []).contains(idHardware)) {
          setState(() {
            logSeguridad = "ACCESO DENEGADO: Dispositivo bloqueado.";
            analizando = false;
          });
          return;
        }
      }

      if (!salidaGlobal) {
        List<NetworkInterface> interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.any,
        );

        if (interfaces.any((i) => i.name.toLowerCase().contains("tun") || i.name.toLowerCase().contains("ppp"))) {
          zonaPermitida = false;
          logSeguridad = "ACCESO DENEGADO: Uso de red virtual (VPN) no permitido.";
        } else {
          bool gpsActivo = await Geolocator.isLocationServiceEnabled();
          if (!gpsActivo) {
            zonaPermitida = false;
            logSeguridad = "GPS desactivado.";
          } else {
            LocationPermission perm = await Geolocator.checkPermission();
            if (perm == LocationPermission.denied) {
              bool aceptado = await _mostrarDivulgacionUbicacion();
              if (aceptado) {
                perm = await Geolocator.requestPermission();
              }
            }
            if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
              zonaPermitida = false;
              logSeguridad = "Permiso de ubicación requerido para verificar derechos de transmisión local.";
            } else {
              Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
              if (pos.isMocked) {
                zonaPermitida = false;
                logSeguridad = "ACCESO DENEGADO: Ubicación simulada detectada.";
              } else {
                bool exclusionBrasil = pos.longitude > -65.35 && pos.latitude > -11.0;
                double distKm = Geolocator.distanceBetween(
                      pos.latitude,
                      pos.longitude,
                      baseLat,
                      baseLng,
                    ) / 1000;
                if (distKm > radioKm || exclusionBrasil) {
                  zonaPermitida = false;
                  logSeguridad = "RESTRICCIÓN GEOGRÁFICA: Señal fuera de cobertura autorizada.";
                }
              }
            }
          }
        }
      }

      final resFeed = await http.get(Uri.parse("$feedJsonUrl?t=${DateTime.now().millisecondsSinceEpoch}"));
      if (resFeed.statusCode == 200) {
        materialesFeed = json.decode(resFeed.body)['feed_noticias'] ?? [];
      }

      setState(() {
        autorizado = true;
        analizando = false;
      });
    } catch (e) {
      setState(() {
        logSeguridad = "ERROR DE SISTEMA: Verifique su conexión.";
        analizando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (analizando) return _construirPantallaCarga();
    if (!autorizado) return _construirPantallaBloqueo();

    return PantallaGlobal(
      urlSenal: streamUrl,
      materiales: materialesFeed,
      appInstanceId: idHardware,
      radioKm: radioKm,
      salidaGlobal: salidaGlobal,
      zonaPermitida: zonaPermitida,
      r2AccessKey: r2AccessKey,
      r2SecretKey: r2SecretKey,
      onRefresh: _ejecutarProtocoloMaestro,
    );
  }

  Widget _construirPantallaCarga() {
    return Scaffold(
      backgroundColor: colorFondoElegante,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png',
              height: 80,
              errorBuilder: (c, e, s) =>
                  const CircularProgressIndicator(color: colorVerdeTva), // Verde
            ),
            const SizedBox(height: 35),
            if (logSeguridad.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  logSeguridad,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _construirPantallaBloqueo() {
    return Scaffold(
      backgroundColor: colorFondoElegante,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 45.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.security_update_warning_rounded,
                color: colorVerdeTva, // Verde
                size: 75,
              ),
              const SizedBox(height: 35),
              const Text(
                "SISTEMA BLOQUEADO",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                logSeguridad,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 45),
              ElevatedButton(
                onPressed: _ejecutarProtocoloMaestro,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorVerdeTva, // Verde
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text(
                  "REINTENTAR",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FranjaClimaHora extends StatefulWidget {
  const FranjaClimaHora({super.key});

  @override
  State<FranjaClimaHora> createState() => _FranjaClimaHoraState();
}

class _FranjaClimaHoraState extends State<FranjaClimaHora> {
  String _fechaHora = "";
  int _idxCiudad = 0;
  Timer? _reloj;
  Timer? _carrusel;

  final List<Map<String, dynamic>> _ciudades = [
    {"nombre": "Riberalta", "lat": -11.0065, "lng": -66.0631, "temp": "--", "code": -1},
    {"nombre": "Guayaramerín", "lat": -10.8256, "lng": -65.3553, "temp": "--", "code": -1},
    {"nombre": "Cobija", "lat": -11.0267, "lng": -68.7692, "temp": "--", "code": -1},
    {"nombre": "Trinidad", "lat": -14.8333, "lng": -64.9000, "temp": "--", "code": -1},
    {"nombre": "La Paz", "lat": -16.5000, "lng": -68.1193, "temp": "--", "code": -1},
    {"nombre": "Cochabamba", "lat": -17.3895, "lng": -66.1568, "temp": "--", "code": -1},
    {"nombre": "Santa Cruz", "lat": -17.8146, "lng": -63.1361, "temp": "--", "code": -1},
  ];

  @override
  void initState() {
    super.initState();
    _actualizarReloj();
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) => _actualizarReloj());
    _cargarClimas();

    _carrusel = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() {
          _idxCiudad = (_idxCiudad + 1) % _ciudades.length;
        });
      }
    });
  }

  void _actualizarReloj() {
    final now = DateTime.now();
    List<String> meses = ["Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"];
    if (mounted) {
      setState(() {
        _fechaHora = "${now.day} ${meses[now.month - 1]} • ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _cargarClimas() async {
    for (var i = 0; i < _ciudades.length; i++) {
      try {
        final res = await http.get(Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=${_ciudades[i]["lat"]}&longitude=${_ciudades[i]["lng"]}&current_weather=true')).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (mounted) {
            setState(() {
              _ciudades[i]["temp"] = "${data['current_weather']['temperature'].round()}°C";
              _ciudades[i]["code"] = data['current_weather']['weathercode'];
            });
          }
        }
      } catch (e) {}
    }
  }

  IconData _getIconoClima(int code) {
    if (code == -1) return Icons.cloud_off_rounded;
    if (code == 0) return Icons.wb_sunny_rounded;
    if (code >= 1 && code <= 3) return Icons.wb_cloudy_rounded;
    if (code >= 45 && code <= 48) return Icons.foggy;
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return Icons.water_drop_rounded;
    if (code >= 71 && code <= 77) return Icons.ac_unit_rounded;
    if (code >= 95 && code <= 99) return Icons.flash_on_rounded;
    return Icons.cloud_rounded;
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _carrusel?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int codeActual = _ciudades[_idxCiudad]['code'];
    final Color iconColor = codeActual == 0
        ? Colors.yellowAccent
        : (codeActual >= 51 && codeActual <= 67 ? Colors.lightBlueAccent : Colors.white70);

    return Container(
      color: colorVerdeTva, // FRANJA EN VERDE AMAZONÍA
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _fechaHora,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          Row(
            children: [
              Icon(_getIconoClima(codeActual), color: iconColor, size: 16),
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: Text(
                  "${_ciudades[_idxCiudad]['nombre']} ${_ciudades[_idxCiudad]['temp']}",
                  key: ValueKey<int>(_idxCiudad),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SliverFranjaDelegate extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 34.0;
  @override
  double get maxExtent => 34.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return const FranjaClimaHora();
  }

  @override
  bool shouldRebuild(covariant _SliverFranjaDelegate oldDelegate) => false;
}

class EscanerCastingRadar extends StatefulWidget {
  const EscanerCastingRadar({super.key});

  @override
  State<EscanerCastingRadar> createState() => _EscanerCastingRadarState();
}

class _EscanerCastingRadarState extends State<EscanerCastingRadar> {
  static const _castPlatform = MethodChannel('com.avrorasoft.tva/cast');
  bool _buscando = true;
  final List<String> _dispositivosEncontrados = [];

  @override
  void initState() {
    super.initState();
    _iniciarEscaneoRed();
  }

  Future<void> _iniciarEscaneoRed() async {
    final MDnsClient client = MDnsClient();
    try {
      await client.start();

      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_googlecast._tcp.local'),
      )) {
        await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          if (mounted && !_dispositivosEncontrados.contains(srv.target)) {
            setState(() {
              _dispositivosEncontrados.add(srv.target.replaceAll('.local', ' (Chromecast/Android TV)'));
            });
          }
        }
      }

      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_airplay._tcp.local'),
      )) {
        await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          if (mounted && !_dispositivosEncontrados.contains(srv.target)) {
            setState(() {
              _dispositivosEncontrados.add(srv.target.replaceAll('.local', ' (AirPlay/Smart TV)'));
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error en mDNS: $e");
    } finally {
      client.stop();
      if (mounted) {
        setState(() {
          _buscando = false;
        });
      }
    }
  }

  void _conectarDispositivo(String nombre) async {
    try {
      await _castPlatform.invokeMethod('openCastMenu');
    } catch (e) {
      debugPrint("Fallo al invocar casting nativo: $e");
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(25),
      height: 400,
      decoration: const BoxDecoration(
        color: colorTarjetaOscura,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cast_connected_rounded,
                color: colorVerdeTva, // Verde
                size: 28,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Transmitir a la TV",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Colors.white,
                  ),
                ),
              ),
              if (_buscando)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: colorVerdeTva, // Verde
                    strokeWidth: 2,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            "Buscando pantallas en tu red Wi-Fi...",
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const Divider(height: 30, color: Colors.white12),
          Expanded(
            child: _dispositivosEncontrados.isEmpty
                ? Center(
                    child: Text(
                      _buscando
                          ? "Rastreando dispositivos..."
                          : "No se encontraron televisores compatibles en esta red.",
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: _dispositivosEncontrados.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        leading: const Icon(
                          Icons.tv_rounded,
                          color: Colors.white70,
                        ),
                        title: Text(
                          _dispositivosEncontrados[index],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white24,
                        ),
                        onTap: () => _conectarDispositivo(
                          _dispositivosEncontrados[index],
                        ),
                      );
                    },
                  ),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                _dispositivosEncontrados.clear();
                setState(() {
                  _buscando = true;
                });
                _iniciarEscaneoRed();
              },
              child: const Text(
                "VOLVER A BUSCAR",
                style: TextStyle(
                  color: colorVerdeTva, // Verde
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PantallaGlobal extends StatefulWidget {
  final String urlSenal;
  final List<dynamic> materiales;
  final String appInstanceId;
  final double radioKm;
  final bool salidaGlobal;
  final bool zonaPermitida;
  final String r2AccessKey;
  final String r2SecretKey;
  final VoidCallback onRefresh;

  const PantallaGlobal({
    super.key,
    required this.urlSenal,
    required this.materiales,
    required this.appInstanceId,
    required this.radioKm,
    required this.salidaGlobal,
    required this.zonaPermitida,
    required this.r2AccessKey,
    required this.r2SecretKey,
    required this.onRefresh,
  });

  @override
  State<PantallaGlobal> createState() => _PantallaGlobalState();
}

class _PantallaGlobalState extends State<PantallaGlobal> with WidgetsBindingObserver {
  final ScrollController _scrollMaster = ScrollController();
  late VideoPlayerController _videoLiveController;
  Timer? _watchdogTimer;

  bool _liveInit = false;
  bool _liveError = false;
  bool _playerAnclado = false;
  bool _inmersionActiva = false;
  bool _mostrarRetorno = false;

  // LÓGICA DE GRABACIÓN - UN SOLO CLIC
  bool _estaGrabando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.zonaPermitida) {
      _iniciarLiveSoberano();
    }

    _scrollMaster.addListener(() {
      if (!_playerAnclado && _scrollMaster.offset > 350) {
        if (!_mostrarRetorno) setState(() => _mostrarRetorno = true);
      } else {
        if (_mostrarRetorno) setState(() => _mostrarRetorno = false);
      }
    });

    activeMediaNotifier.addListener(_onGlobalMediaChanged);
  }

  void _onGlobalMediaChanged() {
    if (activeMediaNotifier.value.isNotEmpty && activeMediaNotifier.value != "LIVE_TV") {
      if (_videoLiveController.value.isPlaying) {
        _videoLiveController.pause();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.zonaPermitida) return;
    if (state == AppLifecycleState.resumed) {
      if (_liveInit && !_liveError && (_playerAnclado || _scrollMaster.offset < 50)) {
        if (activeMediaNotifier.value.isEmpty || activeMediaNotifier.value == "LIVE_TV") {
          _videoLiveController.play();
          activeMediaNotifier.value = "LIVE_TV";
        }
      }
    } else if (state == AppLifecycleState.paused) {
      if (_liveInit) _videoLiveController.pause();
    }
  }

  void _iniciarLiveSoberano() {
    setState(() {
      _liveError = false;
    });

    String urlSegura = widget.urlSenal.replaceAll('http://', 'https://');

    _videoLiveController = VideoPlayerController.networkUrl(
      Uri.parse(urlSegura),
      videoPlayerOptions: VideoPlayerOptions(
        allowBackgroundPlayback: false,
        mixWithOthers: true,
      ),
    )..initialize().then((_) {
        // === APLICAR ESTABILIZADOR DE AUDIO ===
        ServicioNormalizadorAudio().normalizarVolumen(_videoLiveController);

        if (mounted) {
          setState(() {
            _liveInit = true;
          });
          if (activeMediaNotifier.value.isEmpty || activeMediaNotifier.value == "LIVE_TV") {
            _videoLiveController.play();
            activeMediaNotifier.value = "LIVE_TV";
          }
        }
      }).catchError((error) {
        if (mounted)
          setState(() {
            _liveError = true;
          });
      });

    _videoLiveController.addListener(() {
      if (_videoLiveController.value.hasError && !_liveError) {
        if (mounted)
          setState(() {
            _liveError = true;
          });
        _reiniciarStream();
      }

      if (_videoLiveController.value.isBuffering) {
        if (_watchdogTimer == null || !_watchdogTimer!.isActive) {
          _watchdogTimer = Timer(const Duration(seconds: 6), () {
            if (mounted && _videoLiveController.value.isBuffering) {
              _reiniciarStream();
            }
          });
        }
      } else {
        _watchdogTimer?.cancel();
      }
    });
  }

  void _reiniciarStream() {
    _watchdogTimer?.cancel();
    _videoLiveController.dispose();
    _liveInit = false;
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && widget.zonaPermitida) _iniciarLiveSoberano();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    activeMediaNotifier.removeListener(_onGlobalMediaChanged);
    _watchdogTimer?.cancel();
    _scrollMaster.dispose();
    if (widget.zonaPermitida) _videoLiveController.dispose();
    super.dispose();
  }

  void _irAMaterialInmersivo(String urlVideo) async {
    activeMediaNotifier.value = urlVideo;
    if (widget.zonaPermitida && _liveInit) _videoLiveController.pause();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => ReproductorVODForzado(urlVideo: urlVideo),
      ),
    );

    if (mounted && widget.zonaPermitida && _liveInit && !_liveError) {
      if (_playerAnclado || _scrollMaster.offset < 50) {
        _videoLiveController.play();
        activeMediaNotifier.value = "LIVE_TV";
      }
    }
  }

  void _toggleInmersionVivo() {
    if (!widget.zonaPermitida) return;
    setState(() {
      _inmersionActiva = !_inmersionActiva;
    });
    if (_inmersionActiva) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  void _abrirRadarCasting() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => const EscanerCastingRadar(),
    );
  }

  void _mostrarPagoQR(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (context) => AlertDialog(
        backgroundColor: colorTarjetaOscura,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          "Pagos directos por publicidad",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/qr.png', fit: BoxFit.contain),
            const SizedBox(height: 15),
            const Text(
              "¿Desea descargar el QR de pago para realizar la transferencia bancaria?",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "CANCELAR",
              style: TextStyle(
                color: Colors.white54,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colorVerdeTva), // Verde
            onPressed: () async {
              Navigator.pop(context);
              try {
                final ByteData bytes = await rootBundle.load('assets/qr.png');
                final Uint8List list = bytes.buffer.asUint8List();
                final result = await ImageGallerySaverPlus.saveImage(
                  list,
                  name: "QR_Canal9_tva",
                );
                if (result['isSuccess'] == true && mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text("QR guardado en la galería."),
                      backgroundColor: colorVerdeTva, // Verde éxito
                    ),
                  );
                }
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text("Error al guardar el QR."),
                      backgroundColor: Colors.red,
                    ),
                  );
              }
            },
            child: const Text(
              "DESCARGAR",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _manejadorPlayManual() {
    activeMediaNotifier.value = "LIVE_TV";
    if (!_videoLiveController.value.isPlaying) {
      _videoLiveController.play();
    }
  }

  // MÉTODO: TOGGLE DE GRABACIÓN A UN CLIC
  void _toggleGrabacion() {
    setState(() {
      _estaGrabando = !_estaGrabando;
    });

    if (_estaGrabando) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Grabando crónica...", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Crónica guardada con éxito", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: colorVerdeTva,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final double playerHeight = MediaQuery.of(context).size.width * (9 / 16);
    final double hideThreshold = playerHeight - 10;

    return Scaffold(
      backgroundColor: colorFondoElegante,
      
      // === BOTÓN FLOTANTE DE GRABACIÓN ===
      floatingActionButton: _inmersionActiva ? null : FloatingActionButton(
        backgroundColor: _estaGrabando ? Colors.red : colorVerdeTva,
        elevation: _estaGrabando ? 8 : 4,
        onPressed: _toggleGrabacion,
        child: Icon(
          _estaGrabando ? Icons.stop_rounded : Icons.camera_alt_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),

      body: Stack(
        children: [
          NotificationListener<ScrollUpdateNotification>(
            onNotification: (scrollInfo) {
              if (widget.zonaPermitida && !_playerAnclado && _liveInit) {
                if (scrollInfo.metrics.pixels >= hideThreshold) {
                  if (_videoLiveController.value.isPlaying) _videoLiveController.pause();
                } else {
                  if (!_videoLiveController.value.isPlaying &&
                      (activeMediaNotifier.value.isEmpty || activeMediaNotifier.value == "LIVE_TV")) {
                    _videoLiveController.play();
                    activeMediaNotifier.value = "LIVE_TV";
                  }
                }
              }
              return false;
            },
            child: CustomScrollView(
              controller: _scrollMaster,
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  elevation: 0,
                  backgroundColor: Colors.black,
                  title: const Row(
                    children: [
                      Icon(
                        Icons.tv_rounded,
                        color: colorVerdeTva, // Verde
                        size: 22,
                      ),
                      SizedBox(width: 8),
                      Text(
                        "CANAL 9 ",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        "tva",
                        style: TextStyle(
                          color: colorVerdeTva, // Verde
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(
                        Icons.qr_code_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => _mostrarPagoQR(context),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.cast_connected_rounded,
                        color: Colors.white,
                      ),
                      onPressed: _abrirRadarCasting,
                    ),
                  ],
                ),
                SliverPersistentHeader(
                  pinned: _playerAnclado,
                  delegate: _SliverPlayerDelegate(
                    max: playerHeight,
                    child: VisibilityDetector(
                      key: const Key('live_tv_radar'),
                      onVisibilityChanged: (info) {
                        if (widget.zonaPermitida && !_playerAnclado && _liveInit) {
                          if (info.visibleFraction < 0.05) {
                            if (_videoLiveController.value.isPlaying) _videoLiveController.pause();
                          } else if (info.visibleFraction >= 0.05) {
                            if (!_videoLiveController.value.isPlaying &&
                                (activeMediaNotifier.value.isEmpty || activeMediaNotifier.value == "LIVE_TV")) {
                              _videoLiveController.play();
                              activeMediaNotifier.value = "LIVE_TV";
                            }
                          }
                        }
                      },
                      child: widget.zonaPermitida
                          ? ReproductorSoberanoTV(
                              controlador: _videoLiveController,
                              inicializado: _liveInit,
                              tieneError: _liveError,
                              anclado: _playerAnclado,
                              inmersionActiva: _inmersionActiva,
                              onTogglePin: () {
                                setState(() {
                                  _playerAnclado = !_playerAnclado;
                                  if (_playerAnclado && _liveInit && !_videoLiveController.value.isPlaying) {
                                    _manejadorPlayManual();
                                  }
                                });
                              },
                              onToggleFullscreen: _toggleInmersionVivo,
                              onPlayManual: _manejadorPlayManual,
                              onReconectar: _reiniciarStream,
                            )
                          : Container(
                              color: Colors.black,
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.location_off_rounded,
                                      color: Colors.white54,
                                      size: 40,
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      "Señal en vivo no disponible en su ubicación",
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverFranjaDelegate(),
                ),
                StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance.ref('noticias').onValue,
                  builder: (context, snapshot) {
                    List<dynamic> listaVisual = List.from(widget.materiales);

                    if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                      final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                      List<dynamic> inyectados = data.entries.map((e) {
                        var val = e.value;
                        val['id'] = e.key; 
                        return val;
                      }).toList();

                      inyectados = inyectados.where((item) {
                        return item != null &&
                            item['id'] != null &&
                            item['titulo'] != null &&
                            item['titulo'].toString().trim().isNotEmpty &&
                            item['videoUrl'] != null &&
                            item['estado'] != 'oculto'; 
                      }).toList();

                      for (var inyectado in inyectados) {
                        if (!listaVisual.any((e) => e['id'] == inyectado['id'])) {
                          listaVisual.insert(0, inyectado);
                        }
                      }
                    }

                    listaVisual.sort((a, b) {
                      String idA = a['id']?.toString() ?? "";
                      String idB = b['id']?.toString() ?? "";
                      return idB.compareTo(idA);
                    });

                    return SliverPadding(
                      padding: const EdgeInsets.only(top: 0, bottom: 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          return TarjetaHibridaInteractiva(
                            key: ValueKey(listaVisual[index]['id']),
                            data: listaVisual[index],
                            appInstanceId: widget.appInstanceId,
                            r2AccessKey: widget.r2AccessKey,
                            r2SecretKey: widget.r2SecretKey,
                            onTap: () async {
                              final noticiaActiva = listaVisual[index];

                              if (noticiaActiva['id'] != null) {
                                FirebaseDatabase.instance
                                    .ref('noticias/${noticiaActiva['id']}/vistos')
                                    .runTransaction((Object? v) {
                                  if (v == null) return Transaction.success(1);
                                  return Transaction.success((v as int) + 1);
                                });
                              }

                              final String urlVideo = noticiaActiva['videoUrl']?.toString() ?? "";

                              if (urlVideo.isNotEmpty) {
                                _irAMaterialInmersivo(urlVideo);
                              } else {
                                if (widget.zonaPermitida && _liveInit) _videoLiveController.pause();

                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => NoticiaDetalleScreen(
                                      noticia: noticiaActiva,
                                    ),
                                  ),
                                );

                                if (mounted && widget.zonaPermitida && _liveInit && !_liveError) {
                                  if (_playerAnclado || _scrollMaster.offset < 50) {
                                    _videoLiveController.play();
                                  }
                                }
                              }
                            },
                          );
                        }, childCount: listaVisual.length),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          if (_mostrarRetorno && !_inmersionActiva)
            Positioned(
              left: 20,
              bottom: 40,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: colorVerdeTva, // Verde al volver arriba
                onPressed: () => _scrollMaster.animateTo(
                  0,
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                ),
                child: const Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          if (_inmersionActiva && widget.zonaPermitida)
            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _liveInit ? _videoLiveController.value.aspectRatio : 16 / 9,
                    child: Stack(
                      children: [
                        if (_liveInit && !_liveError) VideoPlayer(_videoLiveController),
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleInmersionVivo,
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.black45,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.fullscreen_exit_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_liveError)
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.white54,
                                  size: 40,
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  "Transmisión interrumpida",
                                  style: TextStyle(color: Colors.white54),
                                ),
                                TextButton(
                                  onPressed: _reiniciarStream,
                                  child: const Text(
                                    "Reconectar",
                                    style: TextStyle(color: colorVerdeTva), // Verde
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SliverPlayerDelegate extends SliverPersistentHeaderDelegate {
  final double max;
  final Widget child;

  _SliverPlayerDelegate({required this.max, required this.child});

  @override
  double get minExtent => max;

  @override
  double get maxExtent => max;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _SliverPlayerDelegate oldDelegate) =>
      max != oldDelegate.max || child != oldDelegate.child;
}

class ReproductorSoberanoTV extends StatelessWidget {
  final VideoPlayerController controlador;
  final bool inicializado;
  final bool tieneError;
  final bool anclado;
  final bool inmersionActiva;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onPlayManual;
  final VoidCallback onReconectar;

  const ReproductorSoberanoTV({
    super.key,
    required this.controlador,
    required this.inicializado,
    required this.tieneError,
    required this.anclado,
    required this.inmersionActiva,
    required this.onTogglePin,
    required this.onToggleFullscreen,
    required this.onPlayManual,
    required this.onReconectar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          if (!inicializado && !tieneError)
            Center(
              child: Image.asset(
                'assets/logo.png',
                height: 60,
                errorBuilder: (c, e, s) =>
                    const CircularProgressIndicator(color: colorVerdeTva), // Verde
              ),
            ),
          if (inicializado && !tieneError)
            Center(
              child: AspectRatio(
                aspectRatio: controlador.value.aspectRatio,
                child: Stack(
                  children: [
                    VideoPlayer(controlador),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: GestureDetector(
                        onTap: onTogglePin,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          child: Icon(
                            anclado ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                            color: anclado ? colorVerdeTva : Colors.white60, // Verde al anclar
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: onToggleFullscreen,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          child: const Icon(
                            Icons.fullscreen_rounded,
                            color: Colors.white70,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: controlador,
                      builder: (context, value, child) {
                        if (!value.isPlaying) {
                          return Center(
                            child: GestureDetector(
                              onTap: onPlayManual,
                              child: Container(
                                padding: const EdgeInsets.all(15),
                                decoration: const BoxDecoration(
                                  color: Colors.black45,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (tieneError)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    color: Colors.white54,
                    size: 40,
                  ),
                  TextButton(
                    onPressed: onReconectar,
                    child: const Text(
                      "Reconectar manual",
                      style: TextStyle(color: colorVerdeTva), // Verde
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ReproductorVODForzado extends StatefulWidget {
  final String urlVideo;
  const ReproductorVODForzado({super.key, required this.urlVideo});

  @override
  State<ReproductorVODForzado> createState() => _ReproductorVODForzadoState();
}

class _ReproductorVODForzadoState extends State<ReproductorVODForzado> {
  VideoPlayerController? _vc;
  ChewieController? _chewieController;
  bool _init = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _inicializarReproductor();
  }

  Future<void> _inicializarReproductor() async {
    try {
      String urlSegura = widget.urlVideo.replaceAll('http://', 'https://');
      _vc = VideoPlayerController.networkUrl(Uri.parse(urlSegura));
      await _vc!.initialize();

      // === APLICAR ESTABILIZADOR DE AUDIO ===
      ServicioNormalizadorAudio().normalizarVolumen(_vc!);

      bool esVertical = _vc!.value.size.height > _vc!.value.size.width;
      if (esVertical) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }

      _chewieController = ChewieController(
        videoPlayerController: _vc!,
        autoPlay: true,
        looping: false,
        aspectRatio: _vc!.value.aspectRatio,
        allowFullScreen: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: colorVerdeTva, // Verde
          handleColor: colorVerdeTva, // Verde
        ),
      );

      if (mounted) {
        setState(() {
          _init = true;
        });
      }
    } catch (e) {
      debugPrint("Error al inicializar controladores de video: $e");
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _vc?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_init) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Image.asset(
            'assets/logo.png',
            height: 80,
            errorBuilder: (c, e, s) =>
                const CircularProgressIndicator(color: colorVerdeTva), // Verde
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Center(
              child: _chewieController != null
                  ? AspectRatio(
                      aspectRatio: _vc!.value.aspectRatio,
                      child: Stack(
                        children: [
                          Chewie(controller: _chewieController!),
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: Padding(
                              padding: const EdgeInsets.all(15.0),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  SystemChrome.setPreferredOrientations([
                                    DeviceOrientation.portraitUp,
                                  ]);
                                  Navigator.pop(context);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const CircularProgressIndicator(color: colorVerdeTva), // Verde
            ),
          ],
        ),
      ),
    );
  }
}