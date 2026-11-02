import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  runApp(const TvaApp());
}

class TvaApp extends StatelessWidget {
  const TvaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tva',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.black,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
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
  final String liveStreamUrl = "https://envivo.canal9.top/live/tv/index.m3u8";
  late VideoPlayerController _videoController;
  late ScrollController _scrollController;
  
  bool _isPlayerInitialized = false;
  bool _isPinned = false; // Controla si el clavito está puesto
  
  List<Map<String, String>> dispositivosEncontrados = [];
  bool estaBuscando = false;

  // --- CONFIGURACIÓN DE CRÓNICAS IA (Archive.org) ---
  final String _archiveAccessKey = "X8X9EN1c2EX2kEzq";
  final String _archiveSecretKey = "8g1jFLmXyex3DXAq";

  // DATOS DE NOTICIAS REALES
  final List<Map<String, dynamic>> noticiasReales = [
    {
      "categoria": "ECONOMÍA",
      "titulo": "Certificaciones para la Castaña",
      "descripcion": "El sector exportador de Riberalta tramita nuevos avales internacionales para la almendra amazónica. Esto busca mejorar la competitividad del producto en mercados europeos y asiáticos de forma progresiva.",
      "fecha": "06/05/2026",
      "imagen": "https://picsum.photos/seed/castana/400/300",
      "esVertical": false
    },
    {
      "categoria": "SALUD",
      "titulo": "Prácticas de la UABJB en marcha",
      "descripcion": "Estudiantes de cuarto año de enfermería de la Universidad Autónoma del Beni inician su despliegue oficial en diversos centros de salud de la ciudad para reforzar el sistema primario.",
      "fecha": "Hoy",
      "imagen": "https://picsum.photos/seed/salud/300/533", 
      "esVertical": true
    },
    {
      "categoria": "AMAZONÍA",
      "titulo": "Tráfico fluvial en el Puerto",
      "descripcion": "Aumenta la actividad de embarcaciones de carga por la estabilidad del caudal en el Río Beni. Los comerciantes envían vituallas y herramientas hacia las comunidades ribereñas de forma fluida.",
      "fecha": "Hace 2h",
      "imagen": "https://picsum.photos/seed/rio/400/300",
      "esVertical": false
    },
    {
      "categoria": "LOCAL",
      "titulo": "Mototaxistas exigen mantenimiento",
      "descripcion": "El gremio marchó exigiendo la reparación urgente de más de 5 kilómetros de vías urbanas que se encuentran severamente deterioradas por las últimas precipitaciones en la región.",
      "fecha": "Ayer",
      "imagen": "https://picsum.photos/seed/motos/400/300",
      "esVertical": false
    },
    {
      "categoria": "SERVICIOS",
      "titulo": "Cortes de energía programados",
      "descripcion": "ENDE anuncia cortes de suministro eléctrico preventivos en el barrio Los Almendros y zonas aledañas debido a trabajos de mantenimiento en la subestación principal del anillo.",
      "fecha": "Hace 5h",
      "imagen": "https://picsum.photos/seed/luz/300/533",
      "esVertical": true
    },
  ];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_gestionarAudioPlayer);
    _inicializarVideo();
  }

  void _gestionarAudioPlayer() {
    if (!mounted || !_isPlayerInitialized) return;
    
    // Si está anclado, siempre tiene volumen
    if (_isPinned) {
      if (_videoController.value.volume == 0.0) _videoController.setVolume(1.0);
      return;
    }

    // Si el scroll pasa los 150 pixeles (el player ya no se ve), lo mutea
    if (_scrollController.offset > 150.0) {
      if (_videoController.value.volume > 0.0) _videoController.setVolume(0.0);
    } else {
      if (_videoController.value.volume == 0.0) _videoController.setVolume(1.0);
    }
  }

  void _inicializarVideo() {
    try {
      final Uri uri = Uri.parse(liveStreamUrl);
      _videoController = VideoPlayerController.networkUrl(uri)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isPlayerInitialized = true;
            });
            _videoController.play();
          }
        }).catchError((error) {
          debugPrint("Error en motor de video: $error");
        });
    } catch (e) {
      debugPrint("Error al parsear URL: $e");
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_gestionarAudioPlayer);
    _scrollController.dispose();
    _videoController.dispose();
    super.dispose();
  }

  // --- MOTOR DE SUBIDA AUTOMÁTICA ---
  Future<void> ejecutarSubidaAutomatica(String categoria, String titulo, String cuerpo) async {
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String identifier = "tva-${categoria.toLowerCase()}-$timestamp";
    final String url = "http://s3.us.archive.org/$identifier/noticia_$timestamp.txt";

    try {
      final response = await http.put(
        Uri.parse(url),
        headers: {
          "Authorization": "LOW $_archiveAccessKey:$_archiveSecretKey",
          "x-archive-meta-collection": "opensource_media",
          "x-archive-meta-mediatype": "texts",
          "x-archive-meta-title": "CANAL 9 TVA - $categoria: $titulo",
          "x-archive-meta-creator": "Avrora Soft - Vibola LLC",
          "Content-Type": "text/plain",
        },
        body: cuerpo,
      );
      if (response.statusCode == 200) {
        debugPrint("Éxito: Crónica enviada a Archive.org ($identifier)");
      }
    } catch (e) {
      debugPrint("Fallo de conexión: $e");
    }
  }

  // --- DESCUBRIMIENTO DE RED ---
  void _iniciarBusquedaAutomatica() {
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
        String nombreLimpio = ptr.domainName.split('.')[0];
        _agregarDispositivo(nombreLimpio, "Chromecast", "0.0.0.0");
      }
    } catch (e) {
      debugPrint("Fallo mDNS: $e");
    } finally {
      client.stop();
    }
  }

  Future<void> _motorSSDP() async {
    const String multicastAddress = "239.255.255.250";
    const int port = 1900;
    const String query = "M-SEARCH * HTTP/1.1\r\nHOST: $multicastAddress:$port\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: ssdp:all\r\n\r\n";

    try {
      final RawDatagramSocket socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(utf8.encode(query), InternetAddress(multicastAddress), port);

      socket.listen((RawSocketEvent e) {
        if (e == RawSocketEvent.read) {
          Datagram? d = socket.receive();
          if (d != null) {
            String response = utf8.decode(d.data);
            String tipo = response.contains("Roku") ? "Roku" : "DLNA";
            String nombreFinal = response.contains("Roku") ? "Roku Device" : "Smart TV";
            _agregarDispositivo("$nombreFinal (${d.address.address})", tipo, d.address.address);
          }
        }
      });

      Future.delayed(const Duration(seconds: 7), () => socket.close());
    } catch (e) {
      debugPrint("Fallo SSDP: $e");
    }
  }

  void _agregarDispositivo(String nombre, String tipo, String ip) {
    if (!dispositivosEncontrados.any((d) => d['nombre'] == nombre)) {
      if (mounted) setState(() => dispositivosEncontrados.add({'nombre': nombre, 'tipo': tipo, 'ip': ip}));
    }
  }

  Future<void> _conectarADispositivo(Map<String, String> dispositivo) async {
    final String ip = dispositivo['ip']!;
    final String tipo = dispositivo['tipo']!;

    if (tipo == "Roku") {
      final String url = "http://$ip:8060/launch/dev?streamFormat=hls&url=${Uri.encodeComponent(liveStreamUrl)}";
      try { await http.post(Uri.parse(url)); } catch (e) { debugPrint("Error Roku: $e"); }
    } else if (tipo == "DLNA") {
      final String url = "http://$ip:1400/MediaRenderer/AVTransport/Control"; 
      try {
        await http.post(
          Uri.parse(url),
          headers: {
            'SOAPACTION': '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
            'Content-Type': 'text/xml; charset="utf-8"',
          },
          body: '<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><InstanceID>0</InstanceID><CurrentURI>$liveStreamUrl</CurrentURI></u:SetAVTransportURI></s:Body></s:Envelope>'
        );
      } catch (e) { debugPrint("Error DLNA: $e"); }
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Enviando a ${dispositivo['nombre']}..."), backgroundColor: Colors.blueGrey[800]));
    }
  }

  void _mostrarMenuTransmision() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            Timer.periodic(const Duration(milliseconds: 500), (timer) {
              if (mounted) setModalState(() {});
              if (!estaBuscando) timer.cancel();
            });

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: const BoxDecoration(color: Colors.white12)),
                  const SizedBox(height: 25),
                  const Text("PANTALLAS DETECTADAS", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2.0)),
                  const SizedBox(height: 20),
                  Flexible(
                    child: dispositivosEncontrados.isEmpty 
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              if (estaBuscando) const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24))
                              else const Icon(Icons.tv_off, color: Colors.white10, size: 24),
                              const SizedBox(height: 15),
                              Text(estaBuscando ? "Escaneando red local..." : "No se encontraron pantallas", style: const TextStyle(color: Colors.white24, fontSize: 11)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: dispositivosEncontrados.length,
                          itemBuilder: (context, index) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.03)),
                              child: ListTile(
                                visualDensity: VisualDensity.compact,
                                leading: Icon(dispositivosEncontrados[index]['tipo'] == "Chromecast" ? Icons.cast : Icons.tv, size: 16, color: Colors.white38),
                                title: Text(dispositivosEncontrados[index]['nombre']!, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                trailing: const Icon(Icons.play_circle_outline, color: Colors.white24, size: 16),
                                onTap: () => _conectarADispositivo(dispositivosEncontrados[index]),
                              ),
                            );
                          },
                        ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        bool esHorizontal = orientation == Orientation.landscape;
        
        // Calculo matemático del alto del video
        final double playerHeight = MediaQuery.of(context).size.width * (9 / 16);

        if (esHorizontal) {
          // Si giran el dispositivo, pantalla completa simple
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _isPlayerInitialized
                    ? VideoPlayer(_videoController)
                    : const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white10)),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.black,
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Barra superior estática
              SliverAppBar(
                backgroundColor: Colors.black,
                centerTitle: true,
                title: const Text('CANAL 9 TVA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.2)),
                actions: [IconButton(icon: const Icon(Icons.cast_connected, color: Colors.white, size: 20), onPressed: _iniciarBusquedaAutomatica)],
                pinned: true,
                floating: false,
              ),
              // Reproductor que se oculta al hacer scroll (o se queda con el clavito)
              SliverAppBar(
                backgroundColor: Colors.black,
                automaticallyImplyLeading: false,
                expandedHeight: playerHeight,
                collapsedHeight: playerHeight,
                toolbarHeight: playerHeight,
                pinned: _isPinned, // CLAVITO: Controla si se queda fijo o desaparece
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      _isPlayerInitialized
                        ? VideoPlayer(_videoController)
                        : const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white10)),
                      // EL CLAVITO
                      Positioned(
                        top: 5,
                        right: 5,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _isPinned = !_isPinned;
                              _gestionarAudioPlayer(); // Reevalúa audio al cambiar pin
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                            child: Icon(
                              _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                              color: _isPinned ? Colors.blueAccent : Colors.white54,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Título y Botón TV invisible para retornar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 15, bottom: 10),
                  child: Row(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque, // Área grande transparente
                        onTap: () {
                          _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
                        },
                        child: const Padding(
                          padding: EdgeInsets.fromLTRB(15, 10, 10, 10),
                          child: Icon(Icons.tv, size: 14, color: Colors.white30),
                        ),
                      ),
                      const Text(
                        "CRÓNICAS REALES", 
                        style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)
                      ),
                    ],
                  ),
                ),
              ),
              // Lista de Noticias con Textos Encuadrados (Justificados)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => NoticiaDetalleScreen(noticia: noticiasReales[i]),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return FadeTransition(opacity: animation, child: child);
                            },
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 2.0),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F0F0F),
                          borderRadius: BorderRadius.zero,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 6,
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(
                                      noticiasReales[i]['imagen']!, 
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => Container(color: Colors.white10, child: const Icon(Icons.newspaper, color: Colors.white24, size: 24)),
                                    ),
                                    Positioned(
                                      bottom: 0, left: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        color: Colors.blueAccent.withOpacity(0.9),
                                        child: Text(noticiasReales[i]['categoria']!, style: const TextStyle(color: Colors.white, fontSize: 6.5, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    Text(noticiasReales[i]['fecha']!, style: const TextStyle(color: Colors.white38, fontSize: 7, fontWeight: FontWeight.normal)),
                                    const SizedBox(height: 3),
                                    Text(
                                      noticiasReales[i]['titulo']!, 
                                      maxLines: 2, 
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600, height: 1.1)
                                    ),
                                    const SizedBox(height: 3),
                                    // ENCUADRE PERFECTO: Justificado
                                    Text(
                                      noticiasReales[i]['descripcion']!, 
                                      maxLines: 3, 
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.justify, // <-- Alineación encuadrada
                                      style: const TextStyle(color: Colors.white54, fontSize: 7.5, fontWeight: FontWeight.normal, height: 1.1)
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: noticiasReales.length,
                ),
              ),
              // Pie de página comercial
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    Container(
                      width: double.infinity, height: 40,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0A0A0A), 
                        border: Border.symmetric(horizontal: BorderSide(color: Colors.white10, width: 0.5))
                      ),
                      child: const Center(child: Text("AVRORA SOFT - VIBOLA LLC | PUBLICIDAD", style: TextStyle(color: Colors.white10, fontSize: 7, letterSpacing: 1.5))),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: Center(
                        child: Text('Avrora Soft - Vibola LLC', style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }
}

// --- PANTALLA DE DETALLE DE NOTICIA OPTIMIZADA ---
class NoticiaDetalleScreen extends StatefulWidget {
  final Map<String, dynamic> noticia;

  const NoticiaDetalleScreen({super.key, required this.noticia});

  @override
  State<NoticiaDetalleScreen> createState() => _NoticiaDetalleScreenState();
}

class _NoticiaDetalleScreenState extends State<NoticiaDetalleScreen> {
  
  @override
  void initState() {
    super.initState();
    // Bloqueo estricto a vertical si es formato reel
    if (widget.noticia['esVertical'] == true) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
  }

  @override
  void dispose() {
    // Restaurar permisos de rotación al salir
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    super.dispose();
  }

  void _abrirComentarios(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Comentarios", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Escribe tu opinión...",
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.black,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 15),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                child: const Text("Enviar", style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _simularCompartirRedSocial(BuildContext context, String red) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Abriendo $red para compartir..."), backgroundColor: Colors.blueGrey[900], duration: const Duration(seconds: 2))
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool esVertical = widget.noticia['esVertical'];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack( 
          children: [
            // CAPA DE CONTENIDO
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: esVertical ? 9 / 16 : 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          widget.noticia['imagen']!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(color: Colors.white10, child: const Center(child: Icon(Icons.broken_image, color: Colors.white24))),
                        ),
                        const Center(child: Icon(Icons.play_circle_fill, color: Colors.white54, size: 60)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              color: Colors.blueAccent,
                              child: Text(widget.noticia['categoria']!, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                            Text(widget.noticia['fecha']!, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Text(widget.noticia['titulo']!, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, height: 1.2)),
                        const SizedBox(height: 15),
                        // ENCUADRE PERFECTO: Justificado
                        Text(
                          widget.noticia['descripcion']!, 
                          textAlign: TextAlign.justify, // <-- Alineación encuadrada
                          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5, fontWeight: FontWeight.normal)
                        ),
                        
                        const SizedBox(height: 30),
                        const Divider(color: Colors.white10, thickness: 1),
                        const SizedBox(height: 15),

                        // --- REACCIONES (Texto reducido y casi blanco) ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildReaccionBoton(Icons.thumb_up_alt_outlined, "Buenísimo", Colors.cyan),
                            _buildReaccionBoton(Icons.mood_bad, "Me emputa", Colors.red),
                            _buildReaccionBoton(Icons.sentiment_dissatisfied, "¡Qué pena!", Colors.yellow),
                            _buildReaccionBoton(Icons.celebration_outlined, "¡Felicidades!", Colors.green),
                          ],
                        ),
                        
                        const SizedBox(height: 15),
                        const Divider(color: Colors.white10, thickness: 1),
                        const SizedBox(height: 10),

                        // --- CAJA DE COMENTARIOS ---
                        Center(
                          child: InkWell(
                            onTap: () => _abrirComentarios(context),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.chat_bubble_outline, color: Colors.white54, size: 20),
                                  SizedBox(width: 8),
                                  Text("Comentar", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.normal)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 10),
                        const Divider(color: Colors.white10, thickness: 1),
                        const SizedBox(height: 25),

                        // --- COMPARTIR ---
                        const Center(child: Text("COMPARTIR EN", style: TextStyle(color: Colors.white30, fontSize: 10, letterSpacing: 2.0))),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildRedSocialIcon(Icons.facebook, Colors.blue, () => _simularCompartirRedSocial(context, "Facebook")),
                            _buildRedSocialIcon(Icons.tiktok, Colors.white, () => _simularCompartirRedSocial(context, "TikTok")),
                            _buildRedSocialIcon(Icons.chat, Colors.greenAccent, () => _simularCompartirRedSocial(context, "WhatsApp")),
                            _buildRedSocialIcon(Icons.telegram, Colors.lightBlue, () => _simularCompartirRedSocial(context, "Telegram")),
                            _buildRedSocialIcon(Icons.camera_alt, Colors.pinkAccent, () => _simularCompartirRedSocial(context, "Instagram")),
                          ],
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // CAPA SUPERIOR: Botón de retroceso inamovible
            Positioned(
              top: 15,
              left: 15,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReaccionBoton(IconData icono, String texto, Color colorIcono) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icono, color: colorIcono, size: 22),
          onPressed: () {},
          splashRadius: 22,
        ),
        Text(
          texto, 
          // Texto casi blanco y sutil
          style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.normal, fontFamily: 'Roboto')
        ),
      ],
    );
  }

  Widget _buildRedSocialIcon(IconData icono, Color color, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(icono, color: color, size: 20),
        onPressed: onTap,
      ),
    );
  }
}