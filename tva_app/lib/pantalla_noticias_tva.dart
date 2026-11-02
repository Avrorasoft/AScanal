import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

void main() {
  runApp(const AplicacionTVA());
}

class AplicacionTVA extends StatelessWidget {
  const AplicacionTVA({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CANAL 9 TVA-TELEVISIÓN AMAZÓNICA-RIBERALTA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF8B0000), // Rojo oscuro institucional
        useMaterial3: true,
      ),
      // Inyectamos la URL generada por nuestro backend en EDICION-GRANDE
      home: const PantallaNoticiasTVA(
        videoUrl: 'https://vod.canal9.top/video_064035.mp4',
      ),
    );
  }
}

class PantallaNoticiasTVA extends StatefulWidget {
  final String videoUrl;

  const PantallaNoticiasTVA({super.key, required this.videoUrl});

  @override
  State<PantallaNoticiasTVA> createState() => _PantallaNoticiasTVAState();
}

class _PantallaNoticiasTVAState extends State<PantallaNoticiasTVA> {
  late VideoPlayerController _controladorVideo;
  bool _estaInicializado = false;
  bool _hayError = false;

  @override
  void initState() {
    super.initState();
    _inicializarReproductor();
  }

  Future<void> _inicializarReproductor() async {
    try {
      _controladorVideo = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      
      await _controladorVideo.initialize();
      
      setState(() {
        _estaInicializado = true;
      });
      
      // Auto-reproducción al cargar la noticia
      _controladorVideo.play();
      _controladorVideo.setLooping(true);
      
    } catch (error) {
      setState(() {
        _hayError = true;
      });
      debugPrint("Fallo en la carga del video desde R2: $error");
    }
  }

  @override
  void dispose() {
    _controladorVideo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'CANAL 9 TVA',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
        backgroundColor: const Color(0xFF8B0000),
        centerTitle: true,
        elevation: 4.0,
      ),
      body: SafeArea(
        child: Center(
          child: _hayError
              ? _construirMensajeError()
              : _estaInicializado
                  ? _construirReproductor()
                  : const CircularProgressIndicator(
                      color: Color(0xFF8B0000),
                    ),
        ),
      ),
    );
  }

  Widget _construirMensajeError() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, color: Colors.white54, size: 48),
        SizedBox(height: 16),
        Text(
          'No se pudo conectar con el servidor de noticias.',
          style: TextStyle(color: Colors.white),
        ),
      ],
    );
  }

  Widget _construirReproductor() {
    return AspectRatio(
      aspectRatio: _controladorVideo.value.aspectRatio,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(_controladorVideo),
          _CapaDeControles(controlador: _controladorVideo),
          VideoProgressIndicator(
            _controladorVideo,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: Color(0xFF8B0000),
              bufferedColor: Colors.white24,
              backgroundColor: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

class _CapaDeControles extends StatelessWidget {
  final VideoPlayerController controlador;

  const _CapaDeControles({required this.controlador});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        controlador.value.isPlaying ? controlador.pause() : controlador.play();
      },
      child: Container(
        color: Colors.transparent, // Área táctil invisible sobre todo el video
        child: Center(
          child: ValueListenableBuilder(
            valueListenable: controlador,
            builder: (context, VideoPlayerValue valor, child) {
              if (!valor.isPlaying) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 80.0,
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}