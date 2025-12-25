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
                    // 从Flutter获取参数
                    val contactName = call.argument<String>("contactName") ?: "Kira-EN"
                    val characterName = call.argument<String>("characterName") ?: "Kira"
                    // 获取Flutter传递过来的Token
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
        // Initialize TokenManager wrapper
        tokenManager = TokenManager(context)

        // 我们不再强制依赖本地文件加载Token，因为Flutter会传过来
        // 但如果有 SessionManager 的预热逻辑，我们需要先初始化它
        if (tokenManager != null) {
            sessionManager = SessionManager.getInstance(applicationContext, "Kira-EN", 3)
            // 此时可能还没有Token，SessionManager会在Token到来后真正开始工作
            sessionManager?.initialize(tokenManager!!)
        }
    }

    private fun connect(contactName: String, characterName: String, token: String?) {
        if (isConnected) return

        sendEvent("status", "Authenticating...")

        mainScope.launch {
            try {
                // 1. 如果Flutter传来了新Token，立即保存
                if (!token.isNullOrEmpty()) {
                    // 我们传空字符串作为refreshToken，因为API没返回
                    tokenManager?.storeTokens(token, "")
                    Log.i(TAG, "Received and stored new token from Flutter")
                }

                // 2. 获取针对该联系人的 SessionManager
                val mgr = SessionManager.getInstance(applicationContext, contactName, 3)
                if (tokenManager != null) mgr.initialize(tokenManager!!)

                // ==========================================
                // [核心修复]：增加重试等待机制
                // ==========================================
                sendEvent("status", "Finding session...")

                var sessionState: SessionManager.SessionState? = null
                var attempts = 0
                val maxAttempts = 30 // 尝试30次，每次500ms = 最多等待15秒

                while (attempts < maxAttempts) {
                    // 尝试获取会话
                    sessionState = mgr.getBestAvailableSession(contactName)

                    if (sessionState != null) {
                        break // 找到了！退出循环
                    }

                    // 没找到，通知 Flutter 我们在等待（显示 Loading...）
                    val waitPercent = ((attempts.toFloat() / maxAttempts) * 100).toInt()
                    // 这里的 init_progress 会让 Flutter 显示 "Cooking... X%"
                    sendEvent("init_progress", waitPercent)
                    Log.d(TAG, "Waiting for session pool to initialize... attempt $attempts")

                    delay(500) // 等待 500ms 后重试
                    attempts++
                }

                if (sessionState == null) {
                    sendEvent("error", "Timeout: Failed to establish AI connection. Please retry.")
                    return@launch
                }

                // 3. 成功获取会话
                currentSession = sessionState
                sessionManager = mgr
                sesameWebSocket = sessionState.webSocket

                // 4. 设置 WebSocket 回调
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

                // 5. 根据预热状态决定下一步
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
                delay(500)
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
            applyAudioRouting()

            // Setup Player
            val sampleRate = sesameWebSocket?.serverSampleRate ?: 24000
            audioPlayer = AudioPlayer(sampleRate).apply {
                onErrorCallback = { error ->
                    mainScope.launch { sendEvent("error", "Playback: $error") }
                }
            }

            if (startPlaybackImmediately) {
                audioPlayer?.startPlayback()
            }

            // Setup Recorder
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

            // Start Recording
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
                    val delayMs = if (isRunningInCar()) 10L else 5L
                    Thread.sleep(delayMs)
                } catch (e: Exception) {
                    Log.e(TAG, "Audio processing loop error", e)
                    break
                }
            }
            Log.d(TAG, "Audio processing thread stopped")
        }
    }

    private fun applyAudioRouting() {
        systemAudioManager?.let { audioManager ->
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
                    audioManager.isSpeakerphoneOn = false
                    if (audioManager.isBluetoothA2dpOn || audioManager.isBluetoothScoOn) {
                        audioManager.startBluetoothSco()
                        audioManager.isBluetoothScoOn = true
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