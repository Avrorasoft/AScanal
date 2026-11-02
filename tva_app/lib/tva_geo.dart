import 'package:flutter/services.dart' show rootBundle; // Para cargar el JSON
import 'dart:convert'; // Para json.decode
import 'dart:math' as math; // Para math.pi, math.sin, etc.
import 'package:geolocator/geolocator.dart'; // Para Geolocator
import 'package:flutter/material.dart';
import 'main.dart';

extension TvaGeoLogic on _TvaHomeScreenState {
  Future<void> _cargarConfiguracionJSON() async {
    try {
      final String response =
          await rootBundle.loadString('assets/config_tva.json');
      final data = await json.decode(response);
      setState(() {
        _radioPermitidoKm = (data['radio_km'] ?? 150).toDouble();
        _modoGlobal = data['modo_global'] ?? false;
      });
    } catch (e) {
      debugPrint(
          "Archivo config_tva.json no encontrado, usando valores por defecto.");
    }
  }

  Future<void> _verificarGeolocalizacion() async {
    if (_modoGlobal) {
      setState(() => _mostrarPlayer = true);
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _mostrarPlayer = false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _mostrarPlayer = false);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _mostrarPlayer = false);
      return;
    }

    try {
      Position posicion = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      double distanciaKm = _calcularHaversine(
          _latRiberalta, _lonRiberalta, posicion.latitude, posicion.longitude);
      bool enBrasil =
          (posicion.longitude > -65.35 && posicion.latitude > -11.0);

      if (distanciaKm <= _radioPermitidoKm && !enBrasil) {
        setState(() => _mostrarPlayer = true);
      } else {
        setState(() => _mostrarPlayer = false);
      }
    } catch (e) {
      setState(() => _mostrarPlayer = false);
    }
  }

  double _calcularHaversine(
      double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371;
    double dLat = (lat2 - lat1) * math.pi / 180;
    double dLon = (lon2 - lon1) * math.pi / 180;
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }
}
