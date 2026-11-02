import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';

// MANEJADOR EN SEGUNDO PLANO PARA FIREBASE
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Orden PUSH recibida en background: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // INICIALIZACIÓN DE FIREBASE Y SUSCRIPCIÓN AL CANAL DE NOTICIAS
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await FirebaseMessaging.instance.subscribeToTopic('tva_noticias');
  
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const Canal9App());
}

class Canal9App extends StatelessWidget {
  const Canal9App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CANAL 9 TVA-TELEVISIÓN AMAZÓNICA-RIBERALTA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.blueAccent,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: const TvaHomeScreen(),
    );
  }
}

class TvaHomeScreen extends StatefulWidget {
  const TvaHomeScreen({super.key});
  @override
  State<TvaHomeScreen> createState() => _TvaHomeScreenState();
}

class _TvaHomeScreenState extends State<TvaHomeScreen> {
  final String baseJsonUrl = "https://vod.canal9.top/noticias.json";
  final String liveStreamUrl = "https://api.canal9.top/live/amazonia.m3u8";

  late VideoPlayerController _videoController;
  late ScrollController _scrollController;
  Timer? _autoRefreshTimer;
  
  List<dynamic> noticias = [];
  bool cargandoInicial = true;
  bool estaBuscando = false;
  List<Map<String, String>> dispositivosEncontrados = [];
  String horaUltimaSincro = "Conectando...";
  String mensajeErrorDetallado = "";

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _inicializarStreaming();
    _cargarNoticiasIA(esRefrescoForzado: true);
    
    // ESCUCHA ACTIVA DE ÓRDENES PUSH DEL SERVIDOR (EDICION-GRANDE)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['accion'] == 'forzar_actualizacion') {
        debugPrint("MISIL DE SERVIDOR RECIBIDO. ACTUALIZANDO PANTALLA...");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Nuevo material disponible. Actualizando pantalla...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              backgroundColor: Colors.blueAccent,
              duration: Duration(seconds: 3),
            ),
          );
          _cargarNoticiasIA(esRefrescoForzado: true);
        }
      }
    });

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _cargarNoticiasIA(esRefrescoForzado: false);
    });
  }

  Future<void> _cargarNoticiasIA({required bool esRefrescoForzado}) async {
    if (!mounted) return;
    
    if (esRefrescoForzado) {
      setState(() {
        cargandoInicial = true;
        mensajeErrorDetallado = "";
        noticias.clear(); 
      });
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }

    HttpClient httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 15);

    try {
      final int aleatorio = Random().nextInt(9999999);
      final String antiCacheUrl = "$baseJsonUrl?t=${DateTime.now().microsecondsSinceEpoch}&rnd=$aleatorio";
      
      final request = await httpClient.getUrl(Uri.parse(antiCacheUrl));
      request.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate, max-age=0');
      request.headers.set('Pragma', 'no-cache');
      request.headers.set('Expires', '-1');
      
      final response = await request.close();

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        dynamic data;
        try {
          data = json.decode(responseBody);
        } catch (e) {
          throw Exception("JSON corrupto.");
        }

        final ahora = DateTime.now();
        final horaFomateada = "${ahora.hour.toString().padLeft(2, '0')}:${ahora.minute.toString().padLeft(2, '0')}:${ahora.second.toString().padLeft(2, '0')}";

        if (mounted) {
          setState(() {
            noticias = data['feed_noticias'] ?? [];
            horaUltimaSincro = horaFomateada;
            cargandoInicial = false;
            mensajeErrorDetallado = "";
          });
        }
      } else {
        throw Exception("HTTP ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) {
        setState(() {
          cargandoInicial = false;
          mensajeErrorDetallado = e.toString();
          horaUltimaSincro = "Error PUSH";
        });
      }
    } finally {
      httpClient.close(force: true);
    }
  }

  Future<void> _inicializarStreaming() async {
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(liveStreamUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await _videoController.initialize();
      _videoController.play();
      _videoController.setLooping(true);
      _videoController.setVolume(1.0);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Error Streaming: $e");
    }
  }

  void _iniciarBusquedaCasting() {
    setState(() {
      dispositivosEncontrados.clear();
      estaBuscando = true;
    });
    _motormDNS();
    _motorSSDP();
    _mostrarMenuTransmision();
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) setState(() => estaBuscando = false);
    });
  }

  Future<void> _motormDNS() async {
    const String name = '_googlecast._tcp.local';
    final MDnsClient client = MDnsClient();
    await client.start();
    try {
      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(name))) {
        _agregarDispositivo(ptr.domainName.split('.')[0], "Chromecast", "0.0.0.0");
      }
    } finally { client.stop(); }
  }

  Future<void> _motorSSDP() async {
    const String multicast = "239.255.255.250";
    String query = 'M-SEARCH * HTTP/1.1\r\nHOST: $multicast:1900\r\nMAN: "ssdp:discover"\r\nMX: 3\r\nST: ssdp:all\r\n\r\n';
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(utf8.encode(query), InternetAddress(multicast), 1900);
      socket.listen((e) {
        if (e == RawSocketEvent.read) {
          final d = socket.receive();
          if (d != null) {
            String res = utf8.decode(d.data);
            String nombre = res.contains("LG") ? "LG WebOS TV" : (res.contains("Samsung") ? "Samsung Tizen" : "Smart TV");
            _agregarDispositivo("$nombre (${d.address.address})", "DLNA", d.address.address);
          }
        }
      });
      Future.delayed(const Duration(seconds: 7), () => socket.close());
    } catch (_) {}
  }

  void _agregarDispositivo(String n, String t, String i) {
    if (!dispositivosEncontrados.any((d) => d['ip'] == i)) {
      if (mounted) setState(() => dispositivosEncontrados.add({'nombre': n, 'tipo': t, 'ip': i}));
    }
  }

  Future<void> _conectarPantalla(Map<String, String> d) async {
    final String ip = d['ip']!;
    final url = "http://$ip:8357/MediaRenderer/AVTransport/Control";
    final httpClient = HttpClient();
    try {
      final request = await httpClient.postUrl(Uri.parse(url));
      request.headers.set('SOAPACTION', '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"');
      request.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      request.write('<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><InstanceID>0</InstanceID><CurrentURI>$liveStreamUrl</CurrentURI></u:SetAVTransportURI></s:Body></s:Envelope>');
      await request.close();
      
      final playReq = await httpClient.postUrl(Uri.parse(url));
      playReq.headers.set('SOAPACTION', '"urn:schemas-upnp-org:service:AVTransport:1#Play"');
      playReq.write('...');
      await playReq.close();
    } catch (_) {
    } finally {
      httpClient.close(force: true);
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _videoController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: RefreshIndicator(
        onRefresh: () => _cargarNoticiasIA(esRefrescoForzado: true),
        color: Colors.blueAccent,
        backgroundColor: const Color(0xFF1A1A1A),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 240,
              pinned: true,
              backgroundColor: Colors.black,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("CANAL 9 TVA", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
                    Text("Sincronizado: $horaUltimaSincro", style: const TextStyle(color: Colors.blueAccent, fontSize: 8, fontWeight: FontWeight.normal)),
                  ],
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_videoController.value.isInitialized)
                      Center(child: AspectRatio(aspectRatio: _videoController.value.aspectRatio, child: VideoPlayer(_videoController)))
                    else
                      const Center(child: CircularProgressIndicator(color: Colors.white24)),
                    const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent, Colors.black]))),
                  ],
                ),
              ),
              actions: [
                IconButton(icon: const Icon(Icons.cast, color: Colors.white), onPressed: _iniciarBusquedaCasting),
                const SizedBox(width: 10),
              ],
            ),
            if (cargandoInicial)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Colors.blueAccent)))
            else if (mensajeErrorDetallado.isNotEmpty && noticias.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 50),
                        const SizedBox(height: 15),
                        const Text("Falla de Conexión", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Text(
                          mensajeErrorDetallado,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(top: 10, bottom: 80),
                sliver: SliverList(
                  key: ValueKey("lista_${horaUltimaSincro}_${noticias.length}"),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildCardNoticia(noticias[index]),
                    childCount: noticias.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _cargarNoticiasIA(esRefrescoForzado: true),
        backgroundColor: Colors.blueAccent,
        icon: const Icon(Icons.sync, color: Colors.white),
        label: const Text("ACTUALIZAR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildCardNoticia(dynamic n) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => NoticiaDetalleScreen(noticia: n)),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFF121212), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.network(
                n['imagen'], 
                height: 200, 
                width: double.infinity, 
                fit: BoxFit.cover, 
                key: ValueKey("${n['imagen']}_${Random().nextInt(1000)}"),
                errorBuilder: (c, e, s) => Container(height: 200, color: Colors.white10, child: const Center(child: Icon(Icons.broken_image, color: Colors.white38)))
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n['fecha'] ?? "", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 6),
                  Text((n['categoria'] ?? "SOCIAL").toString().toUpperCase(), style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Text(n['titulo'] ?? "", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(n['descripcion'] ?? "", maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarMenuTransmision() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("PANTALLAS DETECTADAS", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            if (dispositivosEncontrados.isEmpty)
              const Padding(padding: EdgeInsets.all(20), child: Text("Buscando...", style: TextStyle(color: Colors.white24)))
            else
              ...dispositivosEncontrados.map((d) => ListTile(
                leading: const Icon(Icons.tv, color: Colors.blueAccent),
                title: Text(d['nombre']!),
                onTap: () {
                  Navigator.pop(context);
                  _conectarPantalla(d);
                },
              )),
          ],
        ),
      ),
    );
  }
}

class NoticiaDetalleScreen extends StatefulWidget {
  final dynamic noticia;
  const NoticiaDetalleScreen({super.key, required this.noticia});

  @override
  State<NoticiaDetalleScreen> createState() => _NoticiaDetalleScreenState();
}

class _NoticiaDetalleScreenState extends State<NoticiaDetalleScreen> {
  VideoPlayerController? _reproductorVideo;
  bool _videoInicializado = false;

  @override
  void initState() {
    super.initState();
    if (widget.noticia['videoUrl'] != null && widget.noticia['videoUrl'].toString().isNotEmpty) {
      _reproductorVideo = VideoPlayerController.networkUrl(Uri.parse(widget.noticia['videoUrl']))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _videoInicializado = true;
            });
            _reproductorVideo!.play();
          }
        });
    }
  }

  @override
  void dispose() {
    _reproductorVideo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.noticia['categoria'] ?? "INFO", style: const TextStyle(fontSize: 14, color: Colors.blueAccent)),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_reproductorVideo != null)
              _videoInicializado
                  ? AspectRatio(
                      aspectRatio: _reproductorVideo!.value.aspectRatio,
                      child: VideoPlayer(_reproductorVideo!),
                    )
                  : const SizedBox(height: 250, child: Center(child: CircularProgressIndicator()))
            else
              Image.network(
                widget.noticia['imagen'], 
                width: double.infinity, 
                height: 250, 
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => Container(height: 250, color: Colors.white10, child: const Center(child: Icon(Icons.broken_image, color: Colors.white38)))
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.noticia['titulo'] ?? "",
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.noticia['fecha'] ?? "",
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.noticia['descripcion'] ?? "",
                    style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _reproductorVideo != null && _videoInicializado
          ? FloatingActionButton(
              backgroundColor: Colors.blueAccent,
              onPressed: () {
                setState(() {
                  _reproductorVideo!.value.isPlaying ? _reproductorVideo!.pause() : _reproductorVideo!.play();
                });
              },
              child: Icon(
                _reproductorVideo!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}