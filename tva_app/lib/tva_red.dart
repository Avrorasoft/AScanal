import 'package:flutter/material.dart';
import 'main.dart';

extension TvaRedLogic on _TvaHomeScreenState {
  Future<void> _gestionarSubidaMaterial() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        File archivoVideo = File(result.files.single.path!);
        _mostrarDialogoSubida(archivoVideo);
      }
    } catch (e) {
      debugPrint("Error en FilePicker: $e");
    }
  }

  void _mostrarDialogoSubida(File archivo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            _ejecutarCargaServidor(archivo, dialogContext);
            return AlertDialog(
              backgroundColor: const Color(0xFF141414),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              title: const Text("Subiendo Crónica",
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.blueAccent),
                  const SizedBox(height: 20),
                  const Text("Procesando material audiovisual...",
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 5),
                  Text(
                      "${(archivo.lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB",
                      style:
                          const TextStyle(color: Colors.white30, fontSize: 10)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _ejecutarCargaServidor(
      File archivo, BuildContext dialogContext) async {
    final String uploadUrl = "https://api.canal9.top/upload_cronica";
    try {
      var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      request.files
          .add(await http.MultipartFile.fromPath('video', archivo.path));
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        Navigator.pop(dialogContext);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Material subido exitosamente."),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(dialogContext);
    }
  }

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
      await for (final PtrResourceRecord ptr in client
          .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(name))) {
        String nombreLimpio = ptr.domainName.split('.')[0];
        _agregarDispositivo(nombreLimpio, "Chromecast", "0.0.0.0");
      }
    } catch (e) {
      debugPrint("Error mDNS: $e");
    } finally {
      client.stop();
    }
  }

  Future<void> _motorSSDP() async {
    const String multicastAddress = "239.255.255.250";
    String query =
        'M-SEARCH * HTTP/1.1\r\nHOST: $multicastAddress:1900\r\nMAN: "ssdp:discover"\r\nMX: 3\r\nST: ssdp:all\r\n\r\n';
    try {
      final RawDatagramSocket socket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(utf8.encode(query), InternetAddress(multicastAddress), 1900);
      socket.listen((RawSocketEvent e) {
        if (e == RawSocketEvent.read) {
          Datagram? d = socket.receive();
          if (d != null) {
            String response = utf8.decode(d.data);
            String tipo = response.contains("Roku") ? "Roku" : "DLNA";
            String nombreFinal = "Smart TV";
            if (response.contains("LG")) nombreFinal = "LG WebOS TV";
            if (response.contains("Samsung")) nombreFinal = "Samsung Tizen";
            _agregarDispositivo(
                "$nombreFinal (${d.address.address})", tipo, d.address.address);
          }
        }
      });
      Future.delayed(const Duration(seconds: 7), () => socket.close());
    } catch (e) {
      debugPrint("Error SSDP: $e");
    }
  }

  void _agregarDispositivo(String nombre, String tipo, String ip) {
    if (!dispositivosEncontrados.any((d) => d['ip'] == ip)) {
      if (mounted)
        setState(() => dispositivosEncontrados
            .add({'nombre': nombre, 'tipo': tipo, 'ip': ip}));
    }
  }

  Future<void> _conectarADispositivo(Map<String, String> dispositivo) async {
    final String ip = dispositivo['ip']!;
    final String tipo = dispositivo['tipo']!;
    bool conectado = false;

    // PUERTOS INCLUYENDO EL ESPECÍFICO DE TU LG (1.13)
    List<String> puertos = ["8080", "8357", "1400", "2870", "1900", "49152"];

    try {
      if (tipo == "Roku") {
        final String url =
            "http://$ip:8060/launch/dev?streamFormat=hls&url=${Uri.encodeComponent(liveStreamUrl)}";
        await http.post(Uri.parse(url)).timeout(const Duration(seconds: 5));
        conectado = true;
      } else {
        for (String puerto in puertos) {
          if (conectado) break;
          try {
            final String url =
                "http://$ip:$puerto/MediaRenderer/AVTransport/Control";
            var res = await http
                .post(Uri.parse(url),
                    headers: {
                      'SOAPACTION':
                          '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
                      'Content-Type': 'text/xml; charset="utf-8"',
                      'HOST': '$ip:$puerto',
                      'USER-AGENT': 'LG-NAS-DLNA-CP/1.0 DLNADOC/1.50'
                    },
                    body:
                        '<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><InstanceID>0</InstanceID><CurrentURI>$liveStreamUrl</CurrentURI></u:SetAVTransportURI></s:Body></s:Envelope>')
                .timeout(const Duration(milliseconds: 2000));

            if (res.statusCode == 200) {
              await http.post(Uri.parse(url),
                  headers: {
                    'SOAPACTION':
                        '"urn:schemas-upnp-org:service:AVTransport:1#Play"',
                    'Content-Type': 'text/xml; charset="utf-8"',
                    'HOST': '$ip:$puerto'
                  },
                  body:
                      '<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><InstanceID>0</InstanceID><Speed>1</Speed></u:Play></s:Body></s:Envelope>');
              conectado = true;
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint("Fallo casting: $e");
    }

    if (!conectado && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Error de conexión local."),
          backgroundColor: Colors.red));
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
            height: MediaQuery.of(context).size.height * 0.5,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                        child: Container(
                            width: 40,
                            height: 4,
                            decoration:
                                const BoxDecoration(color: Colors.white12))),
                    const SizedBox(height: 25),
                    const Text("PANTALLAS DETECTADAS",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0)),
                    const SizedBox(height: 20),
                    Expanded(
                      child: dispositivosEncontrados.isEmpty
                          ? Center(
                              child: Text(
                                  estaBuscando
                                      ? "Escaneando red local..."
                                      : "No se encontraron pantallas",
                                  style: const TextStyle(
                                      color: Colors.white24, fontSize: 11)))
                          : ListView.builder(
                              itemCount: dispositivosEncontrados.length,
                              itemBuilder: (context, index) {
                                return ListTile(
                                  visualDensity: VisualDensity.compact,
                                  leading: const Icon(Icons.tv,
                                      size: 16, color: Colors.white38),
                                  title: Text(
                                      dispositivosEncontrados[index]['nombre']!,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 13)),
                                  trailing: const Icon(
                                      Icons.play_circle_outline,
                                      color: Colors.white24,
                                      size: 16),
                                  onTap: () => _conectarADispositivo(
                                      dispositivosEncontrados[index]),
                                );
                              },
                            ),
                    ),
                  ],
                ),
                if (estaBuscando)
                  const Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.blueAccent))),
                  ),
              ],
            ),
          );
        });
      },
    );
  }
}
