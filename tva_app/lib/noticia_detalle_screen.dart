import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:audioplayers/audioplayers.dart';

class NoticiaDetalleScreen extends StatefulWidget {
  final Map<String, dynamic> noticia;

  const NoticiaDetalleScreen({Key? key, required this.noticia}) : super(key: key);

  @override
  _NoticiaDetalleScreenState createState() => _NoticiaDetalleScreenState();
}

class _NoticiaDetalleScreenState extends State<NoticiaDetalleScreen> {
  late AudioPlayer _audioPlayer;
  late ScrollController _scrollController;
  
  bool isReadingMode = true; 
  bool isPlayingAudio = false;
  int _currentCarouselIndex = 0; 
  bool _mostrarBotonSubir = false; 

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _scrollController = ScrollController();
    
    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() {
          isPlayingAudio = false;
        });
      }
    });

    _scrollController.addListener(() {
      if (_scrollController.offset > 150 && !_mostrarBotonSubir) {
        setState(() => _mostrarBotonSubir = true);
      } else if (_scrollController.offset <= 150 && _mostrarBotonSubir) {
        setState(() => _mostrarBotonSubir = false);
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleMode(bool toReading) async {
    setState(() {
      isReadingMode = toReading;
    });

    if (toReading) {
      await _audioPlayer.pause();
      setState(() => isPlayingAudio = false);
    } else {
      if (widget.noticia['audioUrl'] != null && widget.noticia['audioUrl'].toString().isNotEmpty) {
        await _audioPlayer.play(UrlSource(widget.noticia['audioUrl']));
        setState(() => isPlayingAudio = true);
      }
    }
  }

  void _volverAlPrincipio() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final noticia = widget.noticia;
    final String titulo = noticia['titulo'] ?? 'Sin título';
    final String texto = noticia['cuerpo_completo'] ?? noticia['descripcion'] ?? '';
    final String audioUrl = noticia['audioUrl'] ?? '';
    final String videoUrl = noticia['videoUrl'] ?? '';
    final List<dynamic> galeria = noticia['galeria'] ?? [];
    final String imagenUrl = noticia['imagen'] ?? '';

    final bool hasAudio = audioUrl.isNotEmpty;
    final bool hasVideo = videoUrl.isNotEmpty;

    final double alturaVisual = MediaQuery.of(context).size.height * 0.38;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          Column(
            children: [
              // ==========================================
              // 1. ZONA VISUAL ANCLADA
              // ==========================================
              SizedBox(
                height: alturaVisual > 320 ? 320 : alturaVisual,
                width: double.infinity,
                child: hasVideo
                    ? Container(
                        color: Colors.black,
                        child: const Center(
                          child: Text("🎥 [Reproductor de video]", style: TextStyle(color: Colors.white54)),
                        ),
                      )
                    : galeria.isNotEmpty
                        ? Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              CarouselSlider(
                                options: CarouselOptions(
                                  height: double.infinity,
                                  autoPlay: true,
                                  autoPlayInterval: const Duration(seconds: 6),
                                  autoPlayAnimationDuration: const Duration(milliseconds: 800),
                                  enlargeCenterPage: false,
                                  viewportFraction: 1.0,
                                  onPageChanged: (index, reason) {
                                    setState(() {
                                      _currentCarouselIndex = index;
                                    });
                                  },
                                ),
                                items: galeria.map((url) {
                                  return Builder(
                                    builder: (BuildContext context) {
                                      return Image.network(
                                        url,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        errorBuilder: (c, e, s) => const Icon(Icons.error, color: Colors.white),
                                      );
                                    },
                                  );
                                }).toList(),
                              ),
                              Positioned(
                                bottom: 15,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: galeria.asMap().entries.map((entry) {
                                    return Container(
                                      width: 8.0,
                                      height: 8.0,
                                      margin: const EdgeInsets.symmetric(horizontal: 4.0),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withOpacity(
                                            _currentCarouselIndex == entry.key ? 0.9 : 0.4),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.5),
                                            blurRadius: 2,
                                          )
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          )
                        : imagenUrl.isNotEmpty
                            ? Image.network(
                                imagenUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                              )
                            : Container(color: Colors.black),
              ),

              // ==========================================
              // 2. ÁREA DE TEXTO Y CONTROLES (EFECTO PREMIUM)
              // ==========================================
              Expanded(
                child: ShaderMask(
                  // EFECTO PREMIUM: Desvanecimiento justo antes de tocar la foto
                  shaderCallback: (Rect rect) {
                    return const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.white, Colors.white],
                      stops: [0.0, 0.05, 1.0], // El 5% superior es el área de desvanecimiento
                    ).createShader(rect);
                  },
                  blendMode: BlendMode.dstIn,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 15), // Separación de descanso al inicio
                        
                        // TITULAR
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 10.0),
                          child: Text(
                            titulo,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),

                        // CONTROLES DUALES
                        if (!hasVideo && hasAudio)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isReadingMode ? const Color(0xFF0078D7) : Colors.grey[800],
                                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _toggleMode(true),
                                    child: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.menu_book, color: Colors.white, size: 18),
                                          SizedBox(width: 6),
                                          Text("LEER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: !isReadingMode ? Colors.purpleAccent : Colors.grey[800],
                                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () {
                                      if (!isReadingMode && isPlayingAudio) {
                                        _audioPlayer.pause();
                                        setState(() => isPlayingAudio = false);
                                      } else {
                                        _toggleMode(false);
                                      }
                                    },
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(isPlayingAudio ? Icons.pause_circle_filled : Icons.headphones, color: Colors.white, size: 18),
                                          const SizedBox(width: 6),
                                          Text(isPlayingAudio ? "ESCUCHANDO" : "ESCUCHAR", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // CONTENIDO INFERIOR
                        if (isReadingMode && !hasVideo)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
                            child: Text(
                              texto,
                              style: const TextStyle(fontSize: 16, height: 1.6, color: Color(0xFFE0E0E0)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ==========================================
          // 3. BOTÓN DE RETROCESO FLOTANTE
          // ==========================================
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 15,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.only(right: 2.0),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),

          // ==========================================
          // 4. BOTÓN DE SUBIR AL PRINCIPIO
          // ==========================================
          if (_mostrarBotonSubir)
            Positioned(
              bottom: 20,
              right: 20,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: const Color(0xFF0078D7).withOpacity(0.9),
                onPressed: _volverAlPrincipio,
                child: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 28),
              ),
            ),
        ],
      ),
    );
  }
}