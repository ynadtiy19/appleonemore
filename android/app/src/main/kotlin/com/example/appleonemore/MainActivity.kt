package com.example.appleonemore

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Bundle
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import kotlin.concurrent.thread
import com.example.appleonemore.SessionManager
import com.example.appleonemore.TokenManager
import com.example.appleonemore.SesameWebSocket
import com.example.appleonemore.AudioPlayer
import com.example.appleonemore.AudioFileProcessor

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL_CONTROL = "com.sesame.voicechat/control"
        private const val CHANNEL_EVENTS = "com.sesame.voicechat/events"
    }

    // Core components
    private var sesameWebSocket: SesameWebSocket? = null
    private var audioRecordManager: com.example.appleonemore.AudioManager? = null
    private var audioPlayer: AudioPlayer? = null
    private var systemAudioManager: AudioManager? = null
    private var tokenManager: TokenManager? = null
    private var sessionManager: SessionManager? = null

    // State
    private var isConnected = false
    private var isMuted = false
    private var currentSession: SessionManager.SessionState? = null
    private var audioProcessingThread: Thread? = null

    // Coroutine scope for Main thread operations
    private val mainScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // Flutter Event Sink
    private var eventSink: EventChannel.EventSink? = null

    // Audio Routing Enum
    enum class AudioRoute {
        AUTO, SPEAKER, EARPIECE, WIRED_HEADSET, BLUETOOTH
    }
    private var currentAudioRoute = AudioRoute.AUTO

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Initialize System Audio
        systemAudioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // 2. Initialize Managers
        setupManagers()

        // 3. Setup Event Channel (Native -> Flutter)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    Log.d(TAG, "Flutter EventChannel attached")
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    Log.d(TAG, "Flutter EventChannel detached")
                }
            }
        )

        // 4. Setup Method Channel (Flutter -> Native)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_CONTROL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val contactName = call.argument<String>("contactName") ?: "Kira-EN"
                    val characterName = call.argument<String>("characterName") ?: "Kira"
                    val token = call.argument<String>("token")

                    if (hasRequiredPermissions()) {
                        connect(contactName, characterName, token)
                        result.success(true)
                    } else {
                        result.error("PERMISSION_DENIED", "Microphone permission is required", null)
                    }
                }
                "disconnect" -> {
                    disconnect()
                    result.success(true)
                }
                "toggleMute" -> {
                    toggleMute()
                    result.success(isMuted)
                }
                "setAudioRoute" -> {
                    val routeName = call.argument<String>("route") ?: "AUTO"
                    setAudioRoute(routeName)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setupManagers() {
        tokenManager = TokenManager(context)
        if (tokenManager != null) {
            sessionManager = SessionManager.getInstance(applicationContext, "Kira-EN", 3)
            sessionManager?.initialize(tokenManager!!)
        }
    }

    private fun connect(contactName: String, characterName: String, token: String?) {
        if (isConnected) return

        sendEvent("status", "Authenticating...")

        mainScope.launch {
            try {
                if (!token.isNullOrEmpty()) {
                    tokenManager?.storeTokens(token, "")
                }

                val mgr = SessionManager.getInstance(applicationContext, contactName, 3)
                if (tokenManager != null) mgr.initialize(tokenManager!!)

                sendEvent("status", "Finding session...")

                var sessionState: SessionManager.SessionState? = null
                var attempts = 0
                val maxAttempts = 30

                while (attempts < maxAttempts) {
                    sessionState = mgr.getBestAvailableSession(contactName)
                    if (sessionState != null) break

                    val waitPercent = ((attempts.toFloat() / maxAttempts) * 100).toInt()
                    sendEvent("init_progress", waitPercent)
                    Log.d(TAG, "Waiting for session pool... attempt $attempts")
                    delay(500)
                    attempts++
                }

                if (sessionState == null) {
                    sendEvent("error", "Timeout: Failed to establish connection.")
                    return@launch
                }

                currentSession = sessionState
                sessionManager = mgr
                sesameWebSocket = sessionState.webSocket

                sessionState.webSocket.apply {
                    onConnectCallback = {
                        mainScope.launch { onWebSocketConnected() }
                    }
                    onDisconnectCallback = {
                        mainScope.launch { onWebSocketDisconnected() }
                    }
                    onErrorCallback = { error ->
                        mainScope.launch {
                            Log.e(TAG, "WebSocket Error: $error")
                            sendEvent("error", error)
                        }
                    }
                }

                if (sessionState.isPromptComplete) {
                    Log.i(TAG, "Session ready, starting audio...")
                    onWebSocketConnected()
                } else {
                    Log.i(TAG, "Session warming up: ${(sessionState.promptProgress * 100).toInt()}%")
                    sendEvent("status", "Initializing...")
                    trackSessionProgress()
                    setupAudio(startPlaybackImmediately = false)
                }

            } catch (e: Exception) {
                Log.e(TAG, "Connection error", e)
                sendEvent("error", "Connection failed: ${e.message}")
            }
        }
    }

    private fun trackSessionProgress() {
        mainScope.launch {
            while (!isConnected) {
                val sessionProgress = sessionManager?.getSessionProgress()

                if (sessionProgress != null) {
                    val (progress, isComplete) = sessionProgress
                    val percent = (progress * 100).toInt()

                    if (isComplete) {
                        sendEvent("init_progress", 100)
                        sendEvent("status", "Ready")
                        audioPlayer?.startPlayback()
                        onWebSocketConnected()
                        break
                    } else {
                        sendEvent("init_progress", percent)
                    }
                }
                delay(200) // Check faster
            }
        }
    }

    private fun onWebSocketConnected() {
        isConnected = true
        sendEvent("status", "Connected")
        if (audioRecordManager == null) {
            setupAudio(startPlaybackImmediately = true)
        }
    }

    private fun onWebSocketDisconnected() {
        if (isConnected) {
            disconnect()
        }
    }

    private fun disconnect() {
        sendEvent("status", "Disconnecting...")
        audioRecordManager?.stopRecording()
        audioPlayer?.stopPlayback()
        isConnected = false
        currentSession?.let { session ->
            sessionManager?.removeSession(session)
        }
        audioRecordManager = null
        audioPlayer = null
        sesameWebSocket = null
        currentSession = null
        resetAudioRouting()
        sendEvent("status", "Disconnected")
    }

    private fun setupAudio(startPlaybackImmediately: Boolean) {
        try {
            val isCarMode = isRunningInCar()
            applyAudioRouting() // [修复] 确保在设置播放器前应用路由

            val sampleRate = sesameWebSocket?.serverSampleRate ?: 24000
            audioPlayer = AudioPlayer(sampleRate).apply {
                onErrorCallback = { error ->
                    mainScope.launch { sendEvent("error", "Playback: $error") }
                }
            }

            if (startPlaybackImmediately) {
                audioPlayer?.startPlayback()
            }

            audioRecordManager = com.example.appleonemore.AudioManager().apply {
                adjustForCarMode(isCarMode)
                setDebugMode(false)
                onAudioDataCallback = { audioData, hasVoice ->
                    if (isConnected) {
                        if (hasVoice) {
                            sesameWebSocket?.sendAudioData(audioData)
                            mainScope.launch { sendEvent("voice_activity", true) }
                        } else {
                            val silentData = ByteArray(audioData.size) { 0 }
                            sesameWebSocket?.sendAudioData(silentData)
                            mainScope.launch { sendEvent("voice_activity", false) }
                        }
                    }
                }
                onErrorCallback = { error ->
                    mainScope.launch { sendEvent("error", "Recording: $error") }
                }
            }

            if (audioRecordManager?.startRecording() == true) {
                startAudioProcessing()
            } else {
                sendEvent("error", "Failed to start microphone")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Audio setup error", e)
            sendEvent("error", "Audio setup failed: ${e.message}")
        }
    }

    private fun startAudioProcessing() {
        if (audioProcessingThread != null && audioProcessingThread!!.isAlive) return
        audioProcessingThread = thread {
            while (isConnected && sesameWebSocket?.isConnected() == true) {
                try {
                    val audioChunk = sesameWebSocket?.getNextAudioChunk()
                    if (audioChunk != null) {
                        audioPlayer?.queueAudioData(audioChunk)
                    }
                    // [优化] 减少处理线程的休眠时间以降低延迟
                    val delayMs = if (isRunningInCar()) 5L else 2L
                    Thread.sleep(delayMs)
                } catch (e: Exception) {
                    Log.e(TAG, "Audio processing loop error", e)
                    break
                }
            }
        }
    }

    private fun applyAudioRouting() {
        systemAudioManager?.let { audioManager ->
            // [修复] 通话模式是必须的，但还需要配合 Speakerphone
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION

            when (currentAudioRoute) {
                AudioRoute.SPEAKER -> {
                    audioManager.isSpeakerphoneOn = true
                    audioManager.stopBluetoothSco()
                }
                AudioRoute.EARPIECE -> {
                    audioManager.isSpeakerphoneOn = false
                    audioManager.stopBluetoothSco()
                }
                AudioRoute.BLUETOOTH -> {
                    audioManager.isSpeakerphoneOn = false
                    audioManager.startBluetoothSco()
                    audioManager.isBluetoothScoOn = true
                }
                AudioRoute.WIRED_HEADSET -> {
                    audioManager.isSpeakerphoneOn = false
                    audioManager.stopBluetoothSco()
                }
                AudioRoute.AUTO -> {
                    // [核心修复] 如果没有连接耳机/蓝牙，默认强制开启扬声器
                    if (audioManager.isBluetoothA2dpOn || audioManager.isBluetoothScoOn) {
                        audioManager.startBluetoothSco()
                        audioManager.isBluetoothScoOn = true
                        audioManager.isSpeakerphoneOn = false
                        Log.i(TAG, "Audio Routing: AUTO -> Bluetooth")
                    } else if (audioManager.isWiredHeadsetOn) {
                        audioManager.isSpeakerphoneOn = false
                        Log.i(TAG, "Audio Routing: AUTO -> Wired Headset")
                    } else {
                        // 手机外放模式
                        audioManager.isSpeakerphoneOn = true
                        Log.i(TAG, "Audio Routing: AUTO -> Speakerphone (Forced)")
                    }
                }
            }
        }
    }

    private fun setAudioRoute(routeName: String) {
        currentAudioRoute = try {
            AudioRoute.valueOf(routeName)
        } catch (e: Exception) {
            AudioRoute.AUTO
        }
        applyAudioRouting()
    }

    private fun resetAudioRouting() {
        systemAudioManager?.let { audioManager ->
            audioManager.mode = AudioManager.MODE_NORMAL
            audioManager.isSpeakerphoneOn = false
            audioManager.stopBluetoothSco()
            audioManager.isBluetoothScoOn = false
        }
    }

    private fun toggleMute() {
        isMuted = !isMuted
    }

    private fun sendEvent(type: String, value: Any) {
        mainScope.launch {
            val data = mapOf("type" to type, "value" to value)
            eventSink?.success(data)
        }
    }

    private fun hasRequiredPermissions(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }

    private fun isRunningInCar(): Boolean {
        return packageManager.hasSystemFeature(PackageManager.FEATURE_AUTOMOTIVE)
    }

    override fun onDestroy() {
        super.onDestroy()
        disconnect()
        sessionManager?.shutdown()
        mainScope.cancel()
    }
}