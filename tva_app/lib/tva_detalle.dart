import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para SystemChrome y DeviceOrientation
import 'package:video_player/video_player.dart'; // Para VideoPlayerController
import 'package:flutter/material.dart';
import 'main.dart';

class NoticiaDetalleScreen extends StatefulWidget {
  final Map<String, dynamic> noticia;
  const NoticiaDetalleScreen({super.key, required this.noticia});
  @override
  State<NoticiaDetalleScreen> createState() => _NoticiaDetalleScreenState();
}

class _NoticiaDetalleScreenState extends State<NoticiaDetalleScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    if (widget.noticia['esVertical'] == true) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight
      ]);
    }
    _inicializarVideoCronica();
  }

  Future<void> _inicializarVideoCronica() async {
    try {
      final String url = widget.noticia['videoUrl'] ?? '';
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      await _controller.initialize().timeout(const Duration(seconds: 20));

      if (mounted) {
        setState(() {
          _initialized = true;
          _controller.play();
        });
      }
    } catch (e) {
      debugPrint("Error VOD: $e");
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight
    ]);
    super.dispose();
  }

  void _abrirComentarios(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Comentarios",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Escribe tu opinión...",
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.black,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 15),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent),
                child:
                    const Text("Enviar", style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool esVertical = widget.noticia['esVertical'] ?? false;
    final double aspect = _initialized
        ? _controller.value.aspectRatio
        : (esVertical ? 9 / 16 : 16 / 9);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: aspect,
                    child: _error
                        ? const Center(
                            child: Text("Crónica no disponible",
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 10)))
                        : (_initialized
                            ? VideoPlayer(_controller)
                            : const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.blueAccent, strokeWidth: 2))),
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
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  color: Colors.blueAccent,
                                  child: Text(
                                      widget.noticia['categoria'] ?? 'INFO',
                                      style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold))),
                              Text(widget.noticia['fecha'] ?? '',
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 10)),
                            ]),
                        const SizedBox(height: 15),
                        Text(widget.noticia['titulo'] ?? 'Sin título',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                height: 1.2)),
                        const SizedBox(height: 15),
                        Text(widget.noticia['descripcion'] ?? '',
                            textAlign: TextAlign.justify,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.5,
                                fontWeight: FontWeight.normal)),
                        const SizedBox(height: 30),
                        const Divider(color: Colors.white10, thickness: 1),
                        const SizedBox(height: 15),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildReac(Icons.thumb_up_alt_outlined,
                                  "Buenísimo", Colors.cyan),
                              _buildReac(
                                  Icons.mood_bad, "Me emputa", Colors.red),
                            ]),
                        const SizedBox(height: 20),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildReac(Icons.sentiment_dissatisfied,
                                  "¡Qué pena!", Colors.yellow),
                              _buildReac(Icons.celebration_outlined,
                                  "¡Felicidades!", Colors.green),
                            ]),
                        const SizedBox(height: 15),
                        const Divider(color: Colors.white10, thickness: 1),
                        const SizedBox(height: 10),
                        Center(
                          child: InkWell(
                            onTap: () => _abrirComentarios(context),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.chat_bubble_outline,
                                      color: Colors.white54, size: 20),
                                  SizedBox(width: 8),
                                  Text("Comentar",
                                      style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                          fontWeight: FontWeight.normal)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Divider(color: Colors.white10, thickness: 1),
                        const SizedBox(height: 25),
                        const Center(
                            child: Text("COMPARTIR EN",
                                style: TextStyle(
                                    color: Colors.white30,
                                    fontSize: 10,
                                    letterSpacing: 2.0))),
                        const SizedBox(height: 20),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _social(Icons.facebook, Colors.blue),
                              _social(Icons.tiktok, Colors.white),
                              _social(Icons.chat, Colors.greenAccent),
                              _social(Icons.telegram, Colors.lightBlue),
                              _social(Icons.camera_alt, Colors.pinkAccent),
                            ]),
                        const SizedBox(height: 50),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
                top: 15,
                left: 15,
                child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.1))),
                        child: const Icon(Icons.arrow_back_ios_new,
                            color: Colors.white, size: 18)))),
          ],
        ),
      ),
    );
  }

  Widget _buildReac(IconData i, String t, Color c) => Expanded(
          child: Column(children: [
        Icon(i, color: c, size: 28),
        const SizedBox(height: 4),
        Text(t, style: const TextStyle(color: Colors.white70, fontSize: 10))
      ]));
  Widget _social(IconData i, Color c) => Container(
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
      child: IconButton(icon: Icon(i, color: c, size: 20), onPressed: () {}));
}
