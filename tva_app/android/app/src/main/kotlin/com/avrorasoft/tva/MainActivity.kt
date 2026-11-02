package com.avrorasoft.tva

import android.content.Intent
import android.provider.Settings
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val AUDIO_CHANNEL = "com.avrorasoft.tva/audio"
    private val CAST_CHANNEL = "com.avrorasoft.tva/cast"
    private val DEEPLINK_CHANNEL = "com.avrorasoft.tva/deeplink"
    
    private var recorder: MediaRecorder? = null
    private var audioFile: String? = null
    private var initialLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Captura el enlace si la aplicación estaba totalmente cerrada y se arranca desde la URL
        val intent = intent
        val data = intent?.data
        if (data != null) {
            initialLink = data.toString()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Captura el enlace si la aplicación ya estaba abierta flotando en segundo plano
        val data = intent.data
        if (data != null) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, DEEPLINK_CHANNEL).invokeMethod("onLinkReceived", data.toString())
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // --- CANAL DE AUDIO (Mantiene tu grabación nativa) ---
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        if (startRecording(path)) {
                            result.success(true)
                        } else {
                            result.error("ERR_REC", "No se pudo iniciar la grabación", null)
                        }
                    } else {
                        result.error("ERR_PATH", "Ruta nula", null)
                    }
                }
                "stopRecording" -> {
                    val finalPath = stopRecording()
                    if (finalPath != null) {
                        result.success(finalPath)
                    } else {
                        result.error("ERR_STOP", "Error al detener", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // --- CANAL DE CASTING (Motor nativo para Samsung / Smart TVs) ---
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAST_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "openCastMenu") {
                try {
                    // Intento 1: Menú de Cast estándar de Android
                    val intent = Intent(Settings.ACTION_CAST_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    try {
                        // Intento 2: Configuración de Pantalla Inalámbrica (Wireless Display)
                        val intent = Intent("android.settings.WIFI_DISPLAY_SETTINGS")
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e2: Exception) {
                        result.error("UNAVAILABLE", "Radar nativo no disponible en este dispositivo", null)
                    }
                }
            } else {
                result.notImplemented()
            }
        }

        // --- CANAL DE ENLACES PROFUNDOS (Deep Linking) ---
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEEPLINK_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInitialLink") {
                result.success(initialLink)
                initialLink = null // Se limpia inmediatamente para evitar reaperturas repetidas
            } else {
                result.notImplemented()
            }
        }
    }

    private fun startRecording(path: String): Boolean {
        audioFile = path
        recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }

        return try {
            recorder?.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setOutputFile(path)
                prepare()
                start()
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun stopRecording(): String? {
        return try {
            recorder?.apply {
                stop()
                release()
            }
            recorder = null
            audioFile
        } catch (e: Exception) {
            null
        }
    }
}