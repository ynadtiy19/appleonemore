package com.example.appleonemore

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import kotlin.concurrent.thread

class VoiceChatPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        private const val TAG = "VoiceChatPlugin"
        private const val CHANNEL_METHODS = "com.sesame.voicechat/methods"
        private const val CHANNEL_EVENTS = "com.sesame.voicechat/recordStream"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    // Core Components
    private var sesameWebSocket: SesameWebSocket? = null
    private var audioRecordManager: AudioManager? = null
    private var audioPlayer: AudioPlayer? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    // Audio Processing Thread
    private var isProcessingAudio = false

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_METHODS)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, CHANNEL_EVENTS)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connect" -> {
                val idToken = call.argument<String>("idToken")
                if (idToken != null) {
                    val success = connectSession(idToken)
                    result.success(success)
                } else {
                    result.error("INVALID_TOKEN", "Token is null", null)
                }
            }
            "disconnect" -> {
                disconnectSession()
                result.success(true)
            }
            "setMute" -> {
                val isMuted = call.argument<Boolean>("isMuted") ?: false
                // 如果需要静音，可以停止录音或只停止发送数据
                if (isMuted) {
                    audioRecordManager?.stopRecording()
                } else {
                    audioRecordManager?.startRecording()
                }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun connectSession(idToken: String): Boolean {
        Log.i(TAG, "Starting new session...")

        // 1. Initialize WebSocket
        sesameWebSocket = SesameWebSocket(idToken).apply {
            onConnectCallback = {
                Log.i(TAG, "WebSocket Connected! Starting Audio Engine...")
                // WS 连接成功后，启动音频
                startAudioEngine(this.serverSampleRate)
                notifyFlutter("status", "connected")
            }
            onDisconnectCallback = {
                Log.i(TAG, "WebSocket Disconnected")
                stopAudioEngine()
                notifyFlutter("status", "disconnected")
            }
            onErrorCallback = { error ->
                Log.e(TAG, "WebSocket Error: $error")
                notifyFlutter("error", error)
            }
        }

        // 2. Connect WS
        return sesameWebSocket?.connect() ?: false
    }

    private fun startAudioEngine(sampleRate: Int) {
        // --- Player ---
        if (audioPlayer == null) {
            audioPlayer = AudioPlayer(sampleRate)
        } else {
            audioPlayer?.updateSampleRate(sampleRate)
        }
        audioPlayer?.startPlayback()

        // --- Recorder ---
        if (audioRecordManager == null) {
            audioRecordManager = AudioManager()
            audioRecordManager?.onAudioDataCallback = { data, hasVoice ->
                // Send Mic Data to WebSocket
                sesameWebSocket?.sendAudioData(data)

                // Optional: Send data back to Flutter for Viz (RMS animation)
                // 注意：如果数据量太大导致卡顿，可以只发送音量值，或者降频发送
                mainHandler.post {
                    eventSink?.success(mapOf("data" to data, "hasVoice" to hasVoice))
                }
            }
        }
        audioRecordManager?.startRecording()

        // --- Audio Processing Loop (WS -> Player) ---
        isProcessingAudio = true
        thread {
            Log.d(TAG, "Audio processing thread started")
            while (isProcessingAudio && sesameWebSocket?.isConnected() == true) {
                try {
                    val chunk = sesameWebSocket?.getNextAudioChunk()
                    if (chunk != null) {
                        audioPlayer?.queueAudioData(chunk)
                    } else {
                        Thread.sleep(10) // Wait for data
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Audio loop error", e)
                }
            }
        }
    }

    private fun stopAudioEngine() {
        isProcessingAudio = false
        audioRecordManager?.stopRecording()
        audioPlayer?.stopPlayback()
        audioPlayer?.clearQueue()
    }

    private fun disconnectSession() {
        sesameWebSocket?.disconnect()
        stopAudioEngine()
        sesameWebSocket = null
        audioRecordManager = null
        audioPlayer = null
    }

    private fun notifyFlutter(type: String, message: Any) {
        mainHandler.post {
            eventSink?.success(mapOf("type" to type, "value" to message))
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        disconnectSession()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }
}