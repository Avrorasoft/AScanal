import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';

final GlobalKey<NavigatorState> llavedeNavegacionGlobal = GlobalKey<NavigatorState>();
final ValueNotifier<String> activeMediaNotifier = ValueNotifier("");

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        brightness: Brightness.light,
        primaryColor: const Color(0xFFFF2400),
        scaffoldBackgroundColor: Colors.white,
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
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _ejecutarProtocoloMaestro());
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
      final resFeed = await http.get(Uri.parse("$feedJsonUrl?t=${DateTime.now().millisecondsSinceEpoch}"));
      if (resFeed.statusCode == 200) {
        final nuevosMateriales = json.decode(resFeed.body)['feed_noticias'] ?? [];
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
    final snapshot = await FirebaseDatabase.instance.ref('noticias/$idNoticia').get();
    
    if (snapshot.exists) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      final urlVideo = data['videoUrl']?.toString() ?? "";
      
      if (urlVideo.isNotEmpty) {
        FirebaseDatabase.instance.ref('noticias/$idNoticia/vistos').runTransaction((Object? v) {
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.location_on_rounded, color: Color(0xFFFF2400)),
            SizedBox(width: 10),
            Expanded(child: Text("Uso de Ubicación", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          ],
        ),
        content: const Text(
          "Canal 9 tva recopila datos de ubicación para habilitar la transmisión en vivo únicamente cuando la aplicación está en uso. Esto es necesario para garantizar que el contenido se visualice exclusivamente dentro de las zonas geográficas autorizadas por derechos de transmisión.",
          style: TextStyle(fontSize: 13, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("DENEGAR", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF2400)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("ACEPTAR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;
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
        final secureSnapshot = await FirebaseDatabase.instance.ref('secure_config').get().timeout(const Duration(seconds: 10));
        if (secureSnapshot.exists) {
          final secureData = secureSnapshot.value as Map<dynamic, dynamic>;
          r2AccessKey = secureData['r2_access_key'] ?? "";
          r2SecretKey = secureData['r2_secret_key'] ?? "";
        }
      } catch (e) {
        debugPrint("Fallo al obtener llaves: $e");
      }

      final resAccess = await http.get(
        Uri.parse("$accessControlUrl?t=${DateTime.now().millisecondsSinceEpoch}")
      ).timeout(const Duration(seconds: 10));
      
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
                double distKm = Geolocator.distanceBetween(pos.latitude, pos.longitude, baseLat, baseLng) / 1000;
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
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, 
          children: [
            Image.asset('assets/logo.png', height: 80, errorBuilder: (c, e, s) => const CircularProgressIndicator(color: Color(0xFFFF2400))),
            const SizedBox(height: 35),
            if (logSeguridad.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  logSeguridad,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _construirPantallaBloqueo() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 45.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, 
            children: [
              const Icon(Icons.security_update_warning_rounded, color: Color(0xFFFF2400), size: 75),
              const SizedBox(height: 35),
              const Text(
                "SISTEMA BLOQUEADO",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Colors.black),
              ),
              const SizedBox(height: 18),
              Text(
                logSeguridad,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black87, fontSize: 14),
              ),
              const SizedBox(height: 45),
              ElevatedButton(
                onPressed: _ejecutarProtocoloMaestro,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF2400),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text(
                  "REINTENTAR",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
        final res = await http.get(
          Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=${_ciudades[i]["lat"]}&longitude=${_ciudades[i]["lng"]}&current_weather=true')
        ).timeout(const Duration(seconds: 5));
        
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (mounted) {
            setState(() {
              _ciudades[i]["temp"] = "${data['current_weather']['temperature'].round()}°C";
              _ciudades[i]["code"] = data['current_weather']['weathercode'];
            });
          }
        }
      } catch (e) {
      }
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
    final Color iconColor = codeActual == 0 ? Colors.yellowAccent : (codeActual >= 51 && codeActual <= 67 ? Colors.lightBlueAccent : Colors.white70);

    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _fechaHora,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.0),
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
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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
  @override double get minExtent => 34.0;
  @override double get maxExtent => 34.0;
  
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
          ResourceRecordQuery.serverPointer('_googlecast._tcp.local'))) {
        await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName))) {
          if (mounted && !_dispositivosEncontrados.contains(srv.target)) {
            setState(() {
              _dispositivosEncontrados.add(srv.target.replaceAll('.local', ' (Chromecast/Android TV)'));
            });
          }
        }
      }

      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer('_airplay._tcp.local'))) {
        await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName))) {
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
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cast_connected_rounded, color: Color(0xFFFF2400), size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Transmitir a la TV",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              if (_buscando)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Color(0xFFFF2400), strokeWidth: 2),
                )
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            "Buscando pantallas en tu red Wi-Fi...",
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const Divider(height: 30),
          Expanded(
            child: _dispositivosEncontrados.isEmpty
                ? Center(
                    child: Text(
                      _buscando ? "Rastreando dispositivos..." : "No se encontraron televisores compatibles en esta red.",
                      style: const TextStyle(color: Colors.black45, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: _dispositivosEncontrados.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        leading: const Icon(Icons.tv_rounded, color: Colors.black87),
                        title: Text(
                          _dispositivosEncontrados[index],
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black26),
                        onTap: () => _conectarDispositivo(_dispositivosEncontrados[index]),
                      );
                    },
                  ),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                _dispositivosEncontrados.clear();
                setState(() { _buscando = true; });
                _iniciarEscaneoRed();
              },
              child: const Text("VOLVER A BUSCAR", style: TextStyle(color: Color(0xFFFF2400), fontWeight: FontWeight.bold)),
            ),
          )
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
  
  List<GlobalKey> _cardKeys = [];

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
    setState(() { _liveError = false; });
    
    String urlSegura = widget.urlSenal.replaceAll('http://', 'https://');

    _videoLiveController = VideoPlayerController.networkUrl(
      Uri.parse(urlSegura),
      videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false, mixWithOthers: true)
    )..initialize().then((_) {
        if (mounted) {
          setState(() { _liveInit = true; });
          if (activeMediaNotifier.value.isEmpty || activeMediaNotifier.value == "LIVE_TV") {
             _videoLiveController.play();
             activeMediaNotifier.value = "LIVE_TV";
          }
        }
      }).catchError((error) {
        if (mounted) setState(() { _liveError = true; });
      });

    _videoLiveController.addListener(() {
      if (_videoLiveController.value.hasError && !_liveError) {
        if (mounted) setState(() { _liveError = true; });
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
      MaterialPageRoute(builder: (c) => ReproductorVODForzado(urlVideo: urlVideo))
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
    setState(() { _inmersionActiva = !_inmersionActiva; });
    if (_inmersionActiva) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Pagos directos por publicidad", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/qr.png', fit: BoxFit.contain), 
            const SizedBox(height: 15),
            const Text(
              "¿Desea descargar el QR de pago para realizar la transferencia bancaria?", 
              textAlign: TextAlign.center, 
              style: TextStyle(fontSize: 13, color: Colors.black87)
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text("CANCELAR", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF2400)),
            onPressed: () async {
              Navigator.pop(context);
              try {
                final ByteData bytes = await rootBundle.load('assets/qr.png');
                final Uint8List list = bytes.buffer.asUint8List();
                final result = await ImageGallerySaverPlus.saveImage(list, name: "QR_Canal9_tva");
                if (result['isSuccess'] == true && mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("QR guardado en la galería."), backgroundColor: Colors.green));
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Error al guardar el QR."), backgroundColor: Colors.red));
              }
            },
            child: const Text("DESCARGAR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  @override
  Widget build(BuildContext context) {
    final double playerHeight = MediaQuery.of(context).size.width * (9/16);
    final double hideThreshold = playerHeight - 10; 
    
    return Scaffold(
      backgroundColor: Colors.white, 
      body: Stack(
        children: [
          NotificationListener<ScrollUpdateNotification>(
            onNotification: (scrollInfo) {
              if (widget.zonaPermitida && !_playerAnclado && _liveInit) {
                if (scrollInfo.metrics.pixels >= hideThreshold) {
                  if (_videoLiveController.value.isPlaying) _videoLiveController.pause();
                } else {
                  if (!_videoLiveController.value.isPlaying && (activeMediaNotifier.value.isEmpty || activeMediaNotifier.value == "LIVE_TV")) {
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
                  title: const Text("CANAL 9 tva", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.qr_code_rounded, color: Colors.white),
                      onPressed: () => _mostrarPagoQR(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cast_connected_rounded, color: Colors.white),
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
                            if (!_videoLiveController.value.isPlaying && (activeMediaNotifier.value.isEmpty || activeMediaNotifier.value == "LIVE_TV")) {
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
                                  Icon(Icons.location_off_rounded, color: Colors.white54, size: 40),
                                  SizedBox(height: 10),
                                  Text("Señal en vivo no disponible en su ubicación", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                    ),
                  ),
                ),
                
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverFranjaDelegate()
                ),

                StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance.ref('noticias').onValue,
                  builder: (context, snapshot) {
                    List<dynamic> listaVisual = List.from(widget.materiales);
                    
                    if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                      final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                      List<dynamic> inyectados = data.values.toList();
                      
                      for (var inyectado in inyectados) {
                        if (!listaVisual.any((e) => e['id'] == inyectado['id'])) {
                          listaVisual.insert(0, inyectado);
                        }
                      }
                    }

                    listaVisual.sort((a, b) => (b['fecha']?.toString() ?? '').compareTo(a['fecha']?.toString() ?? ''));
                    
                    if (_cardKeys.length != listaVisual.length) {
                      _cardKeys = List.generate(listaVisual.length, (_) => GlobalKey());
                    }

                    return SliverPadding(
                      padding: const EdgeInsets.only(top: 0, bottom: 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          return TarjetaHibridaInteractiva(
                            key: _cardKeys[index], 
                            data: listaVisual[index], 
                            appInstanceId: widget.appInstanceId, 
                            r2AccessKey: widget.r2AccessKey,
                            r2SecretKey: widget.r2SecretKey,
                            onTap: () {
                              if (listaVisual[index]['id'] != null) {
                                FirebaseDatabase.instance.ref('noticias/${listaVisual[index]['id']}/vistos').runTransaction((Object? v) {
                                  if (v == null) return Transaction.success(1);
                                  return Transaction.success((v as int) + 1);
                                });
                              }
                              _irAMaterialInmersivo(listaVisual[index]['videoUrl']?.toString() ?? "");
                            }
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
                backgroundColor: const Color(0xFFFF2400),
                onPressed: () => _scrollMaster.animateTo(0, duration: const Duration(milliseconds: 600), curve: Curves.easeOut),
                child: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 26),
              ),
            ),

          if (_inmersionActiva && widget.zonaPermitida)
            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _liveInit ? _videoLiveController.value.aspectRatio : 16/9,
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
                        if (_liveError) Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.white54, size: 40),
                              const SizedBox(height: 10),
                              const Text("Transmisión interrumpida", style: TextStyle(color: Colors.white54)),
                              TextButton(onPressed: _reiniciarStream, child: const Text("Reconectar", style: TextStyle(color: Color(0xFFFF2400)))),
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
  bool shouldRebuild(covariant _SliverPlayerDelegate oldDelegate) => max != oldDelegate.max || child != oldDelegate.child;
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
    required this.onReconectar
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          if (!inicializado && !tieneError) Center(child: Image.asset('assets/logo.png', height: 60, errorBuilder: (c, e, s) => const CircularProgressIndicator(color: Color(0xFFFF2400)))),
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
                          child: Icon(anclado ? Icons.push_pin_rounded : Icons.push_pin_outlined, color: anclado ? const Color(0xFFFF2400) : Colors.white60, size: 28)
                        )
                      )
                    ),
                    Positioned(
                      bottom: 0, 
                      right: 0, 
                      child: GestureDetector(
                        onTap: onToggleFullscreen, 
                        behavior: HitTestBehavior.opaque, 
                        child: Container(
                          padding: const EdgeInsets.all(20), 
                          child: const Icon(Icons.fullscreen_rounded, color: Colors.white70, size: 30)
                        )
                      )
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
                                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40)
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                )
              )
            ),
          if (tieneError) Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.wifi_off_rounded, color: Colors.white54, size: 40), TextButton(onPressed: onReconectar, child: const Text("Reconectar manual", style: TextStyle(color: Color(0xFFFF2400))))])),
        ],
      ),
    );
  }
}

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
  State<TarjetaHibridaInteractiva> createState() => _TarjetaHibridaInteractivaState();
}

class _TarjetaHibridaInteractivaState extends State<TarjetaHibridaInteractiva> {
  static const _audioPlatform = MethodChannel('com.avrorasoft.tva/audio');
  
  bool _estaGrabando = false;
  bool _isLiked = false;
  final ValueNotifier<int> _likesNotifier = ValueNotifier(0);
  final ValueNotifier<int> _vistosNotifier = ValueNotifier(0);
  final ValueNotifier<List<Map<String, dynamic>>> _comentariosNotifier = ValueNotifier([]);
  final ValueNotifier<int> _totalComentariosNotifier = ValueNotifier(0);
  final ValueNotifier<Map<String, dynamic>> _audioStateNotifier = ValueNotifier({'url': '', 'isPlaying': false, 'progress': 0.0, 'isLoading': false});
  final TextEditingController _controladorTextoComentario = TextEditingController();
  
  String? _miApodo;
  bool _isModoDios = false;
  VideoPlayerController? _reproductorAudioUsuario;

  final String r2Endpoint = "https://da292b98201102181e5228ea157e9980.r2.cloudflarestorage.com/vod-canal9";
  final String r2PublicUrl = "https://vod.canal9.top"; 

  @override
  void initState() {
    super.initState();
    _likesNotifier.value = widget.data['likes'] ?? 0;
    _vistosNotifier.value = int.tryParse(widget.data['vistos']?.toString() ?? '0') ?? 0;
    _verificarLikeLocal();
    _cargarApodoYCentinela();
    _conectarDatosEnTiempoReal();
    activeMediaNotifier.addListener(_onGlobalMediaChanged);
  }

  void _onGlobalMediaChanged() {
    if (activeMediaNotifier.value != _audioStateNotifier.value['url'] && _reproductorAudioUsuario?.value.isPlaying == true) {
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
    
    FirebaseDatabase.instance.ref('noticias/${widget.data['id']}/bueno').onValue.listen((event) {
      if (event.snapshot.value != null && mounted) {
        _likesNotifier.value = int.tryParse(event.snapshot.value.toString()) ?? 0;
      }
    });
    
    FirebaseDatabase.instance.ref('noticias/${widget.data['id']}/vistos').onValue.listen((event) {
      if (event.snapshot.value != null && mounted) {
        _vistosNotifier.value = int.tryParse(event.snapshot.value.toString()) ?? 0;
      }
    });
    
    FirebaseDatabase.instance.ref('comentarios/${widget.data['id']}').onValue.listen((event) {
      if (event.snapshot.value != null && mounted) {
        final map = event.snapshot.value as Map<dynamic, dynamic>;
        List<Map<String, dynamic>> temp = []; 
        int totalSum = 0;
        
        map.forEach((key, val) {
          List<Map<String, String>> respuestasTemp = [];
          if (val['respuestas'] != null) {
            (val['respuestas'] as Map<dynamic, dynamic>).forEach((rKey, rVal) { 
              respuestasTemp.add({
                'key': rKey.toString(), 
                'tipo': rVal['tipo']?.toString() ?? 'texto', 
                'contenido': rVal['contenido'].toString(), 
                'apodo': rVal['apodo']?.toString() ?? 'Anónimo', 
                'oficial': rVal['oficial']?.toString() ?? 'false'
              }); 
            });
          }
          temp.add({
            'key': key.toString(), 
            'tipo': val['tipo'].toString(), 
            'contenido': val['contenido'].toString(), 
            'apodo': val['apodo']?.toString() ?? 'Anónimo', 
            'oficial': val['oficial']?.toString() ?? 'false', 
            'respuestas': respuestasTemp
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
      if (mounted) setState(() { _miApodo = apodo; _isModoDios = true; }); 
    } else if (miKey != null) {
      FirebaseDatabase.instance.ref('seguridad_usuarios/$miKey').onValue.listen((event) async { 
        if (event.snapshot.value == null) { 
          await prefs.remove('apodo_tva'); 
          await prefs.remove('key_tva'); 
          if (mounted) setState(() { _miApodo = null; _isModoDios = false; }); 
        } 
      });
      if (mounted) setState(() { _miApodo = apodo; _isModoDios = false; });
    } else if (apodo != null) { 
      await prefs.remove('apodo_tva'); 
      if (mounted) setState(() { _miApodo = null; _isModoDios = false; }); 
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
    if (_reproductorAudioUsuario != null && _reproductorAudioUsuario!.value.isPlaying) { 
      _reproductorAudioUsuario!.pause(); 
      _audioStateNotifier.value = {'url': '', 'isPlaying': false, 'progress': 0.0, 'isLoading': false}; 
    } 
  }

  Future<void> _accionarAudio(String url) async {
    String urlSegura = url.replaceAll('http://', 'https://');
    
    if (_audioStateNotifier.value['url'] == urlSegura && _reproductorAudioUsuario != null) {
      if (_reproductorAudioUsuario!.value.isPlaying) { 
        _reproductorAudioUsuario!.pause(); 
        _audioStateNotifier.value = {'url': urlSegura, 'isPlaying': false, 'progress': _audioStateNotifier.value['progress'], 'isLoading': false}; 
      } else { 
        activeMediaNotifier.value = urlSegura;
        _reproductorAudioUsuario!.play(); 
        _audioStateNotifier.value = {'url': urlSegura, 'isPlaying': true, 'progress': _audioStateNotifier.value['progress'], 'isLoading': false}; 
      }
      return;
    }
    
    activeMediaNotifier.value = urlSegura;
    _audioStateNotifier.value = {'url': urlSegura, 'isPlaying': false, 'progress': 0.0, 'isLoading': true};
    _reproductorAudioUsuario?.dispose();
    _reproductorAudioUsuario = VideoPlayerController.networkUrl(Uri.parse(urlSegura.trim()));
    
    try {
      await _reproductorAudioUsuario!.initialize(); 
      _reproductorAudioUsuario!.setVolume(1.0); 
      _reproductorAudioUsuario!.play();
      
      _reproductorAudioUsuario!.addListener(() {
        if (mounted && _reproductorAudioUsuario != null) {
          double prog = 0.0; 
          if (_reproductorAudioUsuario!.value.duration.inMilliseconds > 0) {
            prog = _reproductorAudioUsuario!.value.position.inMilliseconds / _reproductorAudioUsuario!.value.duration.inMilliseconds;
          }
          bool playing = _reproductorAudioUsuario!.value.isPlaying;
          
          if (_reproductorAudioUsuario!.value.position >= _reproductorAudioUsuario!.value.duration && _reproductorAudioUsuario!.value.duration > Duration.zero) { 
            _reproductorAudioUsuario!.pause(); 
            _reproductorAudioUsuario!.seekTo(Duration.zero); 
            playing = false; 
            prog = 0.0; 
          }
          
          _audioStateNotifier.value = {'url': urlSegura, 'isPlaying': playing, 'progress': prog, 'isLoading': false};
        }
      });
    } catch (e) { 
      _audioStateNotifier.value = {'url': '', 'isPlaying': false, 'progress': 0.0, 'isLoading': false}; 
    }
  }

  void _darMeGusta() async {
    if (widget.data['id'] == null) return;
    final prefs = await SharedPreferences.getInstance();
    int actual = _likesNotifier.value; 
    
    setState(() { _isLiked = !_isLiked; });
    
    int nuevoValor = _isLiked ? actual + 1 : (actual - 1 < 0 ? 0 : actual - 1);
    _likesNotifier.value = nuevoValor; 
    await prefs.setBool('like_${widget.data['id']}', _isLiked);
    
    FirebaseDatabase.instance.ref('noticias/${widget.data['id']}/bueno').set(nuevoValor);
  }

  void _reportarComentario(String idComentario) {
    FirebaseDatabase.instance.ref('reportes_ugc/$idComentario').set({
      'noticia_id': widget.data['id'],
      'fecha_reporte': DateTime.now().toIso8601String(),
      'reportado_por': _miApodo ?? 'Anónimo',
      'app_instance': widget.appInstanceId
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Contenido reportado y enviado a moderación."), backgroundColor: Colors.orange));
  }

  void _bloquearUsuario(String apodoUsuario) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> bloqueados = prefs.getStringList('usuarios_bloqueados') ?? [];
    if (!bloqueados.contains(apodoUsuario)) {
      bloqueados.add(apodoUsuario);
      await prefs.setStringList('usuarios_bloqueados', bloqueados);
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Usuario bloqueado. No verás más sus comentarios."), backgroundColor: Colors.red));
    setState(() {}); 
  }

  void _mostrarRegistroSeguridad([VoidCallback? alCompletar]) {
    final nombreCtrl = TextEditingController(); 
    final apodoCtrl = TextEditingController(); 
    final whatsappCtrl = TextEditingController();
    
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom), 
        child: Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))), 
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min, 
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: Icon(Icons.verified_user_rounded, color: Color(0xFFFF2400), size: 40)), 
              const SizedBox(height: 15), 
              const Center(child: Text("IDENTIDAD CIUDADANA", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))), 
              const SizedBox(height: 20),
              
              TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: "Nombres y Apellidos", border: OutlineInputBorder(), isDense: true)), 
              const SizedBox(height: 12),
              
              TextField(controller: whatsappCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "WhatsApp (Ej: 71234567)", border: OutlineInputBorder(), isDense: true)), 
              const SizedBox(height: 12),
              
              TextField(controller: apodoCtrl, decoration: const InputDecoration(labelText: "Apodo (Opcional)", border: OutlineInputBorder(), isDense: true)), 
              const SizedBox(height: 15),
              
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), minimumSize: const Size(double.infinity, 50)),
                onPressed: () async {
                  if (nombreCtrl.text.isEmpty || whatsappCtrl.text.isEmpty) return;
                  String apodo = apodoCtrl.text.trim().isNotEmpty ? apodoCtrl.text.trim() : nombreCtrl.text.trim();
                  
                  if (nombreCtrl.text.trim() == "73995224 281103") {
                    final prefs = await SharedPreferences.getInstance(); 
                    await prefs.setString('apodo_tva', "CANAL 9 tva"); 
                    await prefs.setString('key_tva', "ADMIN_MASTER");
                    if (mounted) { 
                      setState(() { _miApodo = "CANAL 9 tva"; _isModoDios = true; }); 
                      Navigator.pop(ctx); 
                      if (alCompletar != null) alCompletar(); 
                    } 
                    return;
                  }
                  
                  String cod = "tva-${Random().nextInt(9999).toString().padLeft(4,'0')}";
                  DatabaseReference refNuevo = FirebaseDatabase.instance.ref('seguridad_usuarios').push();
                  
                  await refNuevo.set({
                    'nombre_real': nombreCtrl.text.trim(), 
                    'apodo': apodo, 
                    'whatsapp': whatsappCtrl.text.trim(), 
                    'app_instance': widget.appInstanceId, 
                    'codigo': cod, 
                    'fecha': DateTime.now().toIso8601String()
                  });
                  
                  await launchUrl(
                    Uri.parse("https://wa.me/59173995224?text=${Uri.encodeComponent("Hola Canal 9 tva. Mi nombre es ${nombreCtrl.text} y mi código es $cod")}"), 
                    mode: LaunchMode.externalApplication
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
                child: const Text("VALIDAR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
        ),
      )
    );
  }

  void _intentarAccion(VoidCallback accionPermitida) { 
    if (_miApodo != null) { 
      accionPermitida(); 
    } else { 
      _mostrarRegistroSeguridad(accionPermitida); 
    } 
  }

  Map<String, String> _firmarPeticionS3(String method, String url, List<int> payload) {
    final accessKey = widget.r2AccessKey; 
    final secretKey = widget.r2SecretKey;
    
    final uri = Uri.parse(url); 
    final host = uri.host; 
    final path = uri.path;
    
    final now = DateTime.now().toUtc();
    final amzDate = "${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}T${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}Z";
    final dateStamp = amzDate.substring(0, 8); 
    
    final payloadHash = sha256.convert(payload).toString();
    final canonicalHeaders = "host:$host\nx-amz-content-sha256:$payloadHash\nx-amz-date:$amzDate\n"; 
    const signedHeaders = "host;x-amz-content-sha256;x-amz-date";
    
    final canonicalRequest = "$method\n$path\n\n$canonicalHeaders\n$signedHeaders\n$payloadHash"; 
    final credentialScope = "$dateStamp/auto/s3/aws4_request";
    final stringToSign = "AWS4-HMAC-SHA256\n$amzDate\n$credentialScope\n${sha256.convert(utf8.encode(canonicalRequest))}";
    
    List<int> sign(List<int> key, String msg) => Hmac(sha256, key).convert(utf8.encode(msg)).bytes;
    
    final kDate = sign(utf8.encode("AWS4$secretKey"), dateStamp);
    final signature = Hmac(sha256, sign(sign(sign(kDate, "auto"), "s3"), "aws4_request")).convert(utf8.encode(stringToSign)).toString();
    
    return {
      'x-amz-date': amzDate, 
      'x-amz-content-sha256': payloadHash, 
      'Authorization': "AWS4-HMAC-SHA256 Credential=$accessKey/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature", 
      'Content-Type': 'audio/x-m4a'
    };
  }

  Future<void> _subirAudioAR2(String path, [String? parentId]) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Subiendo audio a la red..."), backgroundColor: Colors.black87));
    String fileName = "audio_${DateTime.now().millisecondsSinceEpoch}.m4a";
    
    try {
      final file = File(path); 
      final bytes = await file.readAsBytes();
      final url = "$r2Endpoint/$fileName";
      
      var response = await http.put(
        Uri.parse(url), 
        headers: _firmarPeticionS3('PUT', url, bytes), 
        body: bytes
      );
      
      if ((response.statusCode == 200 || response.statusCode == 201) && widget.data['id'] != null) {
        String ruta = parentId == null ? 'comentarios/${widget.data['id']}' : 'comentarios/${widget.data['id']}/$parentId/respuestas';
        FirebaseDatabase.instance.ref(ruta).push().set({
          'tipo': 'audio', 
          'contenido': "$r2PublicUrl/$fileName", 
          'apodo': _miApodo ?? 'Anónimo', 
          'oficial': 'false', 
          'fecha': DateTime.now().toIso8601String()
        });
        
        if (mounted) { 
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Audio publicado correctamente"), backgroundColor: Colors.green)); 
          _abrirModalComentarios(); 
        }
      }
    } catch (e) {
      debugPrint("Error R2: $e");
    }
  }

  void _abrirModalComentarios() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> bloqueados = prefs.getStringList('usuarios_bloqueados') ?? [];

    if (!mounted) return;
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.70, 
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              const SizedBox(height: 10), 
              Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))), 
              const SizedBox(height: 10),
              const Text("Comentarios", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), 
              const Divider(),
              
              Expanded(
                child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: _comentariosNotifier,
                  builder: (context, listaComentariosOriginal, child) {
                    List<Map<String, dynamic>> listaComentarios = listaComentariosOriginal
                        .where((c) => !bloqueados.contains(c['apodo']))
                        .toList();

                    if (listaComentarios.isEmpty) return const Center(child: Text("Sé el primero en opinar.", style: TextStyle(color: Colors.black54)));
                    
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
                            ?.where((r) => !bloqueados.contains(r['apodo']))
                            .toList() ?? [];
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10), 
                                decoration: BoxDecoration(
                                  color: esOficial ? const Color(0xFFFFF4E5) : Colors.transparent, 
                                  borderRadius: BorderRadius.circular(8), 
                                  border: Border.all(color: esOficial ? Colors.orange : Colors.transparent)
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
                                            onTap: () { if (esAudio) _accionarAudio(com['contenido']!); },
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (esAudio) 
                                                  ValueListenableBuilder<Map<String, dynamic>>(
                                                    valueListenable: _audioStateNotifier, 
                                                    builder: (context, audioState, _) { 
                                                      bool isPlaying = audioState['url'] == com['contenido'] && audioState['isPlaying']; 
                                                      bool isLoading = audioState['url'] == com['contenido'] && audioState['isLoading']; 
                                                      if (isLoading) return const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF2400))); 
                                                      return Icon(isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: const Color(0xFFFF2400), size: 30); 
                                                    }
                                                  )
                                                else 
                                                  Icon(esOficial ? Icons.campaign_rounded : Icons.person_pin_rounded, color: esOficial ? Colors.orange : Colors.black45, size: 28),
                                                
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Text(com['apodo']!, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: esOficial ? Colors.orange : Colors.black87)), 
                                                          if (esOficial) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.verified_rounded, color: Colors.blue, size: 14))
                                                        ]
                                                      ),
                                                      Text(esAudio ? "Reporte de voz" : com['contenido']!, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                                                    ],
                                                  )
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert, color: Colors.black38, size: 20),
                                          onSelected: (val) {
                                            if (val == 'borrar') {
                                              FirebaseDatabase.instance.ref('comentarios/${widget.data['id']}/${com['key']}').remove();
                                            } else if (val == 'reportar') {
                                              _reportarComentario(com['key']);
                                            } else if (val == 'bloquear') {
                                              _bloquearUsuario(com['apodo']!);
                                              Navigator.pop(ctx);
                                            }
                                          },
                                          itemBuilder: (BuildContext context) => [
                                            if (puedeBorrar) const PopupMenuItem(value: 'borrar', child: Text("Borrar")),
                                            const PopupMenuItem(value: 'reportar', child: Text("Reportar")),
                                            const PopupMenuItem(value: 'bloquear', child: Text("Bloquear Usuario")),
                                          ],
                                        ),
                                      ],
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight, 
                                      child: InkWell(
                                        onTap: () { 
                                          Navigator.pop(ctx); 
                                          _intentarAccion(() => _mostrarOpcionesRespuesta(com['key'], com['apodo']!)); 
                                        }, 
                                        child: const Padding(padding: EdgeInsets.only(top: 5, right: 5), child: Text("Responder", style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)))
                                      )
                                    )
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
                                        decoration: BoxDecoration(color: respOficial ? const Color(0xFFFFF4E5) : Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: GestureDetector(
                                                behavior: HitTestBehavior.opaque, 
                                                onTap: () { if (respEsAudio) _accionarAudio(resp['contenido']!); },
                                                child: Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    if (respEsAudio) 
                                                      ValueListenableBuilder<Map<String, dynamic>>(
                                                        valueListenable: _audioStateNotifier, 
                                                        builder: (context, audioState, _) { 
                                                          bool isPlaying = audioState['url'] == resp['contenido'] && audioState['isPlaying']; 
                                                          return Icon(isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: const Color(0xFFFF2400), size: 20); 
                                                        }
                                                      )
                                                    else 
                                                      Icon(respOficial ? Icons.campaign_rounded : Icons.subdirectory_arrow_right_rounded, color: respOficial ? Colors.orange : Colors.black38, size: 16),
                                                    
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              Text(resp['apodo']!, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: respOficial ? Colors.orange : Colors.black87))
                                                            ]
                                                          ),
                                                          Text(respEsAudio ? "Respuesta de voz" : resp['contenido']!, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert, color: Colors.black38, size: 16),
                                              onSelected: (val) {
                                                if (val == 'borrar') {
                                                  FirebaseDatabase.instance.ref('comentarios/${widget.data['id']}/${com['key']}/respuestas/${resp['key']}').remove();
                                                } else if (val == 'reportar') {
                                                  _reportarComentario(resp['key']!);
                                                } else if (val == 'bloquear') {
                                                  _bloquearUsuario(resp['apodo']!);
                                                  Navigator.pop(ctx);
                                                }
                                              },
                                              itemBuilder: (BuildContext context) => [
                                                if (puedeBorrarResp) const PopupMenuItem(value: 'borrar', child: Text("Borrar")),
                                                const PopupMenuItem(value: 'reportar', child: Text("Reportar")),
                                                const PopupMenuItem(value: 'bloquear', child: Text("Bloquear Usuario")),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                )
                            ],
                          ),
                        );
                      },
                    );
                  }
                ),
              ),
              Container(
                padding: EdgeInsets.only(left: 15, right: 15, top: 12, bottom: MediaQuery.of(ctx).viewInsets.bottom + 15), 
                decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey[200]!))),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87, 
                          elevation: 0, 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), 
                          padding: const EdgeInsets.symmetric(vertical: 12)
                        ), 
                        icon: const Icon(Icons.keyboard_alt_outlined, color: Colors.white, size: 16), 
                        label: const Text("Escribir", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), 
                        onPressed: () { 
                          Navigator.pop(ctx); 
                          _intentarAccion(() => _mostrarDialogoTexto(null)); 
                        }
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatefulBuilder(
                        builder: (BuildContext context, StateSetter setBtnState) {
                          return GestureDetector(
                            onLongPressStart: (_) => _intentarAccion(() async { 
                              _detenerAudio(); 
                              try { 
                                if (await Permission.microphone.request().isGranted) { 
                                  final dir = await getTemporaryDirectory(); 
                                  String path = '${dir.path}/reporte_${DateTime.now().millisecondsSinceEpoch}.m4a'; 
                                  if (await _audioPlatform.invokeMethod('startRecording', {"path": path, "noiseSuppression": true})) { 
                                    setBtnState(() => _estaGrabando = true); 
                                    HapticFeedback.heavyImpact(); 
                                  } 
                                } 
                              } catch (e) {} 
                            }),
                            onLongPressEnd: (_) async { 
                              if (_estaGrabando) { 
                                try { 
                                  final String? path = await _audioPlatform.invokeMethod('stopRecording'); 
                                  setBtnState(() => _estaGrabando = false); 
                                  if (path != null) { 
                                    HapticFeedback.mediumImpact(); 
                                    Navigator.pop(ctx); 
                                    _subirAudioAR2(path, null); 
                                  } 
                                } catch (e) { 
                                  setBtnState(() => _estaGrabando = false); 
                                } 
                              } 
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150), 
                              padding: const EdgeInsets.symmetric(vertical: 12), 
                              decoration: BoxDecoration(color: _estaGrabando ? Colors.red : Colors.black87, borderRadius: BorderRadius.circular(20)), 
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center, 
                                children: [
                                  Icon(_estaGrabando ? Icons.mic_rounded : Icons.mic_none_rounded, color: Colors.white, size: 16), 
                                  const SizedBox(width: 5), 
                                  Text(_estaGrabando ? "Grabando" : "Voz", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
                                ]
                              )
                            )
                          );
                        }
                      )
                    )
                  ]
                )
              )
            ],
          ),
        );
      }
    ).whenComplete(() { _detenerAudio(); });
  }

  void _mostrarOpcionesRespuesta(String? parentId, [String? responderA]) {
    showModalBottomSheet(
      context: context, 
      backgroundColor: Colors.transparent, 
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(25), 
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))), 
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            const Text("¿Cómo deseas responder?", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), 
            const SizedBox(height: 20), 
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
              children: [
                _BotonOpcionRespuesta(
                  icono: Icons.keyboard_alt_outlined, 
                  texto: "Escrito", 
                  color: Colors.black87, 
                  onTap: () { Navigator.pop(ctx); _mostrarDialogoTexto(parentId, responderA); }
                ), 
                _BotonOpcionRespuesta(
                  icono: Icons.mic_none_rounded, 
                  texto: "Voz", 
                  color: const Color(0xFFFF2400), 
                  onTap: () { Navigator.pop(ctx); _iniciarGrabacionRespuestaRapida(parentId); }
                )
              ]
            )
          ]
        )
      )
    ).whenComplete(() { _detenerAudio(); });
  }

  void _iniciarGrabacionRespuestaRapida(String? parentId) async {
    _detenerAudio();
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white, 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), 
        title: const Text("Grabando...", textAlign: TextAlign.center, style: TextStyle(color: Colors.red, fontWeight: FontWeight.w400, fontSize: 11)), 
        content: const Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            Icon(Icons.mic, color: Colors.red, size: 40), 
            SizedBox(height: 10), 
            Text("Habla ahora para responder", textAlign: TextAlign.center, style: TextStyle(fontSize: 12))
          ]
        ), 
        actionsAlignment: MainAxisAlignment.center, 
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.black87), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), 
            onPressed: () async { 
              try { 
                final String? path = await _audioPlatform.invokeMethod('stopRecording'); 
                if (path != null) { 
                  HapticFeedback.mediumImpact(); 
                  Navigator.pop(ctx); 
                  _subirAudioAR2(path, parentId); 
                } else { 
                  Navigator.pop(ctx); 
                } 
              } catch (e) { Navigator.pop(ctx); } 
            }, 
            child: const Text("Enviar audio", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 11))
          )
        ]
      )
    );
    try { 
      if (await Permission.microphone.request().isGranted) { 
        final dir = await getTemporaryDirectory(); 
        String path = '${dir.path}/reporte_${DateTime.now().millisecondsSinceEpoch}.m4a'; 
        if (await _audioPlatform.invokeMethod('startRecording', {"path": path, "noiseSuppression": true})) {
          HapticFeedback.heavyImpact(); 
        }
      } 
    } catch (e) {}
  }

  void _mostrarDialogoTexto(String? parentId, [String? responderA]) {
    _controladorTextoComentario.clear(); 
    if (responderA != null) _controladorTextoComentario.text = "@$responderA "; 
    bool marcarOficial = false;
    
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(15))), 
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(parentId == null ? "Escribir Comentario" : "Responder", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), 
                  const SizedBox(height: 15),
                  TextField(controller: _controladorTextoComentario, maxLines: 4, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Escriba aquí...", isDense: true)), 
                  const SizedBox(height: 10),
                  if (_isModoDios && parentId == null) 
                    CheckboxListTile(
                      title: const Text("Fijar como Anuncio Oficial", style: TextStyle(color: Color(0xFFFF2400), fontWeight: FontWeight.bold, fontSize: 12)), 
                      value: marcarOficial, 
                      onChanged: (bool? value) { setModalState(() { marcarOficial = value ?? false; }); }, 
                      controlAffinity: ListTileControlAffinity.leading, 
                      activeColor: const Color(0xFFFF2400)
                    ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end, 
                    children: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR", style: TextStyle(color: Colors.black54, fontSize: 12))), 
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF2400)), 
                        onPressed: () { 
                          if(_controladorTextoComentario.text.trim().isNotEmpty && widget.data['id'] != null) { 
                            String ruta = parentId == null ? 'comentarios/${widget.data['id']}' : 'comentarios/${widget.data['id']}/$parentId/respuestas'; 
                            FirebaseDatabase.instance.ref(ruta).push().set({
                              'tipo': 'texto', 
                              'contenido': _controladorTextoComentario.text.trim(), 
                              'apodo': _miApodo ?? 'Anónimo', 
                              'oficial': marcarOficial.toString(), 
                              'fecha': DateTime.now().toIso8601String()
                            }); 
                          } 
                          Navigator.pop(context); 
                          _abrirModalComentarios(); 
                        }, 
                        child: const Text("ENVIAR", style: TextStyle(color: Colors.white, fontSize: 12))
                      )
                    ]
                  )
                ],
              ),
            ),
          );
        }
      ),
    ).whenComplete(() { _detenerAudio(); });
  }

  void _compartirNoticia() {
    String link = widget.data['id'] != null 
        ? "https://vod.canal9.top/noticia/${widget.data['id']}" 
        : "https://play.google.com/store/apps/details?id=com.avrorasoft.tva";
    String textoACompartir = "🔴 NOTICIA - CANAL 9 tva\n${widget.data['titulo'] ?? ''}\n\n📱 Mira el reporte completo y nuestra señal en vivo descargando la app oficial:\n$link";
    Share.share(textoACompartir);
  }

  Widget _iconAction(IconData icon, String value, VoidCallback? onTap, {Color color = Colors.black87}) {
    return GestureDetector(
      onTap: onTap, 
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(icon, size: 24, color: color), 
          if (value.isNotEmpty) const SizedBox(width: 4), 
          if (value.isNotEmpty) Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color))
        ]
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String urlVideo = widget.data['videoUrl']?.toString().trim() ?? "";
    bool esVideo = urlVideo.isNotEmpty && (urlVideo.endsWith('.mp4') || urlVideo.endsWith('.m3u8')); 
    
    String urlImg = widget.data['imagen']?.toString().trim() ?? "";
    if (urlImg.isEmpty && widget.data['imagenes'] != null) {
      List<String> imgs = List<String>.from(widget.data['imagenes']);
      if (imgs.isNotEmpty) urlImg = imgs[0];
    }

    urlImg = urlImg.replaceAll('http://', 'https://');
    
    return Column(
      children: [
        Container(height: 6, width: double.infinity, color: const Color(0xFFF0F0F0)), 
        
        Container(
          color: Colors.white,
          padding: const EdgeInsets.only(top: 15, bottom: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("INFORMACIÓN", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFFFF2400))),
                    Text(widget.data['fecha']?.toUpperCase() ?? "", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF424242))),
                  ]
                )
              ),
              const SizedBox(height: 8),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Text(widget.data['titulo'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF641E16), height: 1.2)),
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
                        Image.network(
                          urlImg, 
                          fit: BoxFit.cover, 
                          width: double.infinity, 
                          height: double.infinity,
                          errorBuilder: (_,__,___) => const Center(child: Icon(Icons.image_not_supported, color: Colors.white24))
                        )
                      else 
                        Image.asset('assets/logo.png', height: 80, color: Colors.white24),
                      
                      if (esVideo) 
                        const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 60)), 
                    ],
                  ),
                ),
              ),
              
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: _likesNotifier, 
                      builder: (context, likes, _) => _iconAction(_isLiked ? Icons.favorite_rounded : Icons.favorite_border, likes.toString(), _darMeGusta, color: _isLiked ? const Color(0xFFFF2400) : Colors.black87)
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _vistosNotifier, 
                      builder: (context, vistos, _) => _iconAction(Icons.visibility_outlined, vistos.toString(), null)
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _totalComentariosNotifier, 
                      builder: (context, comentarios, _) => _iconAction(Icons.chat_bubble_outline, comentarios.toString(), _abrirModalComentarios)
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
      
      bool esVertical = _vc!.value.size.height > _vc!.value.size.width; 
      if (esVertical) { 
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]); 
      } else { 
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft, 
          DeviceOrientation.landscapeRight
        ]); 
      } 
      
      _chewieController = ChewieController(
        videoPlayerController: _vc!, 
        autoPlay: true, 
        looping: false, 
        aspectRatio: _vc!.value.aspectRatio, 
        allowFullScreen: false, 
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFFFF2400), 
          handleColor: const Color(0xFFFF2400)
        )
      ); 
      
      if (mounted) {
        setState(() { _init = true; }); 
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
            errorBuilder: (c, e, s) => const CircularProgressIndicator(color: Color(0xFFFF2400))
          )
        )
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
                                  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                                  Navigator.pop(context);
                                }, 
                                child: Container(
                                  padding: const EdgeInsets.all(12), 
                                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle), 
                                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 30)
                                )
                              )
                            )
                          ),
                        ],
                      ),
                    )
                  : const CircularProgressIndicator(color: Color(0xFFFF2400)),
            ), 
          ]
        ),
      )
    ); 
  }
}