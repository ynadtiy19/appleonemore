package com.example.appleonemore

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class SessionManager private constructor(
    private val context: Context,
    private val contactName: String,
    private val poolSize: Int
) {

    companion object {
        private const val TAG = "SessionManager"
        private val INSTANCES = mutableMapOf<String, SessionManager>()

        fun getInstance(context: Context, contactName: String, poolSize: Int = 8): SessionManager {
            val key = "$contactName-$poolSize"
            return INSTANCES[key] ?: synchronized(this) {
                INSTANCES[key] ?: SessionManager(context.applicationContext, contactName, poolSize).also {
                    INSTANCES[key] = it
                }
            }
        }

        fun getAllInstances(): Map<String, SessionManager> = INSTANCES.toMap()

        fun clearAllInstances() {
            synchronized(this) {
                INSTANCES.values.forEach { it.shutdown() }
                INSTANCES.clear()
            }
        }

        private fun getBackendCharacter(contactName: String): String {
            val character = extractCharacterFromKey(contactName)
            return when (character.lowercase()) {
                "kira" -> "Maya"
                "hugo" -> "Maya"
                else -> character
            }
        }

        private fun extractCharacterFromKey(contactKey: String): String {
            return contactKey.split("-").firstOrNull() ?: contactKey
        }

        private fun extractLanguageFromKey(contactKey: String): String {
            return contactKey.split("-").getOrNull(1) ?: "EN"
        }
    }

    data class SessionState(
        var webSocket: SesameWebSocket,
        val character: String,
        val contactKey: String,
        val language: String,
        val createdAt: Long,
        var isPromptComplete: Boolean = false,
        var promptProgress: Float = 0f,
        var isAvailable: Boolean = true,
        var isInUse: Boolean = false,
        var job: Job
    )

    data class SessionInfo(
        val progress: Float,
        val isComplete: Boolean,
        val isConnected: Boolean
    )

    private val sessionPool = ConcurrentLinkedQueue<SessionState>()
    private val isRunning = AtomicBoolean(false)
    private val pendingCreations = AtomicInteger(0)
    private val sessionCounter = AtomicInteger(0)
    private val creationInProgress = AtomicBoolean(false)
    private lateinit var tokenManager: TokenManager
    private lateinit var audioFileProcessor: AudioFileProcessor
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    fun initialize(tokenManager: TokenManager) {
        this.tokenManager = tokenManager
        this.audioFileProcessor = AudioFileProcessor(context)

        if (isRunning.compareAndSet(false, true)) {
            Log.i(TAG, "[$contactName] Initializing session pool with $poolSize sessions")
            startPoolMaintenance()
        }
    }

    private fun startPoolMaintenance() {
        scope.launch {
            val intervalMs = (60L * 1000L) / poolSize

            while (isRunning.get()) {
                try {
                    val shouldCreateSession = synchronized(this@SessionManager) {
                        val currentSessions = sessionPool.size
                        val pendingSessions = pendingCreations.get()
                        val totalPlanned = currentSessions + pendingSessions

                        when {
                            totalPlanned < poolSize && !creationInProgress.get() -> true
                            else -> false
                        }
                    }

                    if (shouldCreateSession) {
                        createSessionWithTimer()
                    } else {
                        cleanupDeadSessions()
                    }
                    delay(intervalMs)
                } catch (e: Exception) {
                    Log.e(TAG, "[$contactName] Pool maintenance error", e)
                    delay(10000)
                }
            }
        }
    }

    private suspend fun createSessionWithTimer() {
        if (!creationInProgress.compareAndSet(false, true)) return

        try {
            val shouldProceed = synchronized(this@SessionManager) {
                val currentSessions = sessionPool.size
                val pendingSessions = pendingCreations.get()
                if (currentSessions + pendingSessions < poolSize) {
                    pendingCreations.incrementAndGet()
                    true
                } else {
                    false
                }
            }

            if (!shouldProceed) return

            val validToken = tokenManager.getValidIdToken()
            if (validToken == null) {
                Log.e(TAG, "[$contactName] Cannot create session: no valid token")
                return
            }

            val character = getBackendCharacter(contactName)
            val sessionIndex = sessionCounter.incrementAndGet()

            // [优化] 减少会话建立之间的抖动延迟
            val jitter = (500..1500).random()
            val baseDelay = 1000L
            delay(baseDelay + jitter)

            scope.launch {
                try {
                    val webSocket = SesameWebSocket(validToken, character, "RP-Android")

                    if (webSocket.connect()) {
                        var attempts = 0
                        val maxAttempts = 200
                        while (!webSocket.isConnected() && attempts < maxAttempts) {
                            delay(100)
                            attempts++
                        }

                        if (webSocket.isConnected()) {
                            val actualLanguage = extractLanguageFromKey(contactName)
                            val sessionState = SessionState(
                                webSocket = webSocket,
                                character = character,
                                contactKey = contactName,
                                language = actualLanguage,
                                createdAt = System.currentTimeMillis(),
                                job = coroutineContext[Job]!!
                            )

                            sessionPool.offer(sessionState)
                            // 立即开始发送预录制音频
                            sendPreRecordedAudioToSession(webSocket, character, sessionIndex)
                        } else {
                            webSocket.disconnect()
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "[$contactName] Error creating session", e)
                } finally {
                    pendingCreations.decrementAndGet()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "[$contactName] Error in createSessionWithTimer", e)
            pendingCreations.decrementAndGet()
        } finally {
            creationInProgress.set(false)
        }
    }

    private suspend fun cleanupDeadSessions() {
        val currentTime = System.currentTimeMillis()
        val GRACE_PERIOD_MS = 15000L

        synchronized(this@SessionManager) {
            val iterator = sessionPool.iterator()
            while (iterator.hasNext()) {
                val session = iterator.next()
                val sessionAge = currentTime - session.createdAt
                val isOldEnough = sessionAge > GRACE_PERIOD_MS
                val isActuallyDead = !session.webSocket.isConnected() || session.job.isCancelled
                val isMarkedForRemoval = !session.isAvailable && !session.isInUse

                if ((isOldEnough && isActuallyDead) || isMarkedForRemoval) {
                    session.job.cancel()
                    session.webSocket.disconnect()
                    iterator.remove()
                }
            }
        }
    }

    private suspend fun sendPreRecordedAudioToSession(webSocket: SesameWebSocket, character: String, sessionNumber: Int) {
        try {
            val characterName = extractCharacterFromKey(contactName).lowercase()
            val language = extractLanguageFromKey(contactName).lowercase()

            val audioFileName = when (characterName) {
                "kira" -> if (language == "fr") "kira_fr.wav" else "kira_en.wav"
                "hugo" -> if (language == "fr") "hugo_fr.wav" else "hugo_en.wav"
                else -> "kira_en.wav"
            }

            val audioChunks = audioFileProcessor.loadWavFile(audioFileName)
            if (audioChunks != null && audioChunks.isNotEmpty()) {
                val sessionState = sessionPool.find { it.webSocket == webSocket }

                for (i in audioChunks.indices) {
                    val chunk = audioChunks[i]
                    if (!webSocket.isConnected()) break

                    webSocket.sendAudioData(chunk)

                    sessionState?.let { state ->
                        state.promptProgress = (i + 1).toFloat() / audioChunks.size
                    }

                    // [核心修复] 将这里原本的 64ms 延迟极大缩短
                    // 原本是模拟真实语速发送(Real-time)，现在改为极速发送(Upload mode)
                    // 这样服务器可以瞬间接收完整个音频并完成处理
                    delay(5)
                }

                val silenceChunk = ByteArray(2048) { 0 }
                webSocket.sendAudioData(silenceChunk)

                sessionState?.let { state ->
                    state.promptProgress = 1.0f
                    state.isPromptComplete = true
                    state.isAvailable = true
                }

                // 等待服务器处理
                delay(200)

                // 如果 session 此时仍未被用户占用，且已完成预热，为了保持池子新鲜度，
                // 可以考虑在一段时间后替换它。
                sessionState?.let { state ->
                    scope.launch {
                        delay(10000) // 延长保留时间至10秒
                        if (!state.isInUse) {
                            state.job.cancel()
                            state.webSocket.disconnect()
                            sessionPool.remove(state)
                            // 触发重新创建
                            pendingCreations.incrementAndGet()
                            try { createSessionWithTimer() } finally { pendingCreations.decrementAndGet() }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error sending pre-recorded audio", e)
        }
    }

    fun getBestAvailableSession(preferredCharacter: String? = null): SessionState? {
        val backendCharacter = getBackendCharacter(contactName)
        val requestedLanguage = extractLanguageFromKey(contactName)

        val availableSessions = sessionPool.filter {
            it.isAvailable && !it.isInUse && it.webSocket.isConnected() &&
                    it.character == backendCharacter && it.contactKey == contactName &&
                    it.language == requestedLanguage
        }

        val bestSession = availableSessions.maxByOrNull { session ->
            if (session.isPromptComplete) 100f else session.promptProgress
        }

        bestSession?.let { session ->
            session.isInUse = true
        }

        return bestSession
    }

    fun returnSession(sessionState: SessionState) {
        sessionState.isInUse = false
    }

    fun removeSession(sessionState: SessionState) {
        synchronized(this@SessionManager) {
            sessionState.job.cancel()
            sessionState.webSocket.disconnect()
            sessionPool.remove(sessionState)
        }
    }

    fun getPoolStatus(): String {
        val total = sessionPool.size
        return "[$contactName] Pool: $total total"
    }

    fun getSessionProgress(): Pair<Float, Boolean>? {
        val backendCharacter = getBackendCharacter(contactName)
        val contactSessions = sessionPool.filter {
            it.character == backendCharacter && it.contactKey == contactName && it.webSocket.isConnected()
        }

        if (contactSessions.isEmpty()) {
            return null
        }

        val bestSession = contactSessions.maxWithOrNull(compareBy<SessionState> {
            if (it.isPromptComplete) 1000f else it.promptProgress
        }.thenBy { it.promptProgress })

        return bestSession?.let {
            Pair(it.promptProgress, it.isPromptComplete)
        }
    }

    fun getAllSessionsProgress(): List<SessionInfo> {
        return emptyList() // 简化
    }

    fun shutdown() {
        if (isRunning.compareAndSet(true, false)) {
            sessionPool.forEach { session ->
                session.job.cancel()
                session.webSocket.disconnect()
            }
            sessionPool.clear()
            scope.cancel()
        }
    }
}