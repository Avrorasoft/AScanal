import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../utils/tva_constantes.dart';

class ReproductorSoberanoTV extends StatefulWidget {
  final VideoPlayerController controlador;
  final bool inicializado;
  final bool tieneError;
  final bool anclado;
  final bool inmersionActiva;
  final bool zonaPermitida;
  final bool eventoActivo;
  final String eventoTitulo;
  final String eventoFecha; // Formato esperado: YYYY-MM-DDTHH:MM
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
    required this.zonaPermitida,
    required this.eventoActivo,
    required this.eventoTitulo,
    required this.eventoFecha,
    required this.onTogglePin,
    required this.onToggleFullscreen,
    required this.onPlayManual,
    required this.onReconectar,
  });

  @override
  State<ReproductorSoberanoTV> createState() => _ReproductorSoberanoTVState();
}

class _ReproductorSoberanoTVState extends State<ReproductorSoberanoTV> {
  Timer? _timer;
  Duration _tiempoRestante = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (!widget.zonaPermitida && widget.eventoActivo) {
      _iniciarCuentaRegresiva();
    }
  }

  @override
  void didUpdateWidget(covariant ReproductorSoberanoTV oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.zonaPermitida && widget.eventoActivo) {
      if (_timer == null || !oldWidget.eventoActivo || oldWidget.eventoFecha != widget.eventoFecha) {
        _iniciarCuentaRegresiva();
      }
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _iniciarCuentaRegresiva() {
    _timer?.cancel();
    if (widget.eventoFecha.isEmpty) return;

    try {
      DateTime fechaEvento = DateTime.parse(widget.eventoFecha);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            final ahora = DateTime.now();
            if (fechaEvento.isAfter(ahora)) {
              _tiempoRestante = fechaEvento.difference(ahora);
            } else {
              _tiempoRestante = Duration.zero;
              _timer?.cancel();
            }
          });
        }
      });
    } catch (e) {
      debugPrint("Error parseando fecha del evento: $e");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatearDuracion(Duration duracion) {
    String dias = duracion.inDays.toString().padLeft(2, '0');
    String horas = (duracion.inHours % 24).toString().padLeft(2, '0');
    String minutos = (duracion.inMinutes % 60).toString().padLeft(2, '0');
    String segundos = (duracion.inSeconds % 60).toString().padLeft(2, '0');
    return "${dias}d : ${horas}h : ${minutos}m : ${segundos}s";
  }

  Widget _construirPanelEventoGlobal() {
    return Container(
      color: Colors.black,
      width: double.infinity,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/logo.png', height: 60, color: Colors.white24),
            const SizedBox(height: 20),
            if (widget.eventoActivo && widget.eventoTitulo.isNotEmpty) ...[
              const Icon(Icons.public_rounded, color: colorVerdeTva, size: 28),
              const SizedBox(height: 8),
              Text(
                "PRÓXIMA TRANSMISIÓN GLOBAL",
                style: const TextStyle(
                  color: colorVerdeTva,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  widget.eventoTitulo.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF181818),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  _formatearDuracion(_tiempoRestante),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    fontFamily: 'Courier',
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.zonaPermitida) {
      return _construirPanelEventoGlobal();
    }

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          if (!widget.inicializado && !widget.tieneError)
            Center(
              child: Image.asset(
                'assets/logo.png',
                height: 60,
                errorBuilder: (c, e, s) => const CircularProgressIndicator(color: colorVerdeTva),
              ),
            ),
          if (widget.inicializado && !widget.tieneError)
            Center(
              child: AspectRatio(
                aspectRatio: widget.controlador.value.aspectRatio,
                child: Stack(
                  children: [
                    VideoPlayer(widget.controlador),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: GestureDetector(
                        onTap: widget.onTogglePin,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          child: Icon(
                            widget.anclado ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                            color: widget.anclado ? colorVerdeTva : Colors.white60,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: widget.onToggleFullscreen,
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
                      valueListenable: widget.controlador,
                      builder: (context, value, child) {
                        if (!value.isPlaying) {
                          return Center(
                            child: GestureDetector(
                              onTap: widget.onPlayManual,
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
          if (widget.tieneError)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off_rounded, color: Colors.white54, size: 40),
                  TextButton(
                    onPressed: widget.onReconectar,
                    child: const Text("Reconectar manual", style: TextStyle(color: colorVerdeTva)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}