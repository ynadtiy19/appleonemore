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

        // Map app contact names to backend character names
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
        // [修改] 默认为 true，因为不再需要预热
        var isPromptComplete: Boolean = true,
        var promptProgress: Float = 1.0f,
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
    // [删除] AudioFileProcessor 不再需要
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    fun initialize(tokenManager: TokenManager) {
        this.tokenManager = tokenManager

        if (isRunning.compareAndSet(false, true)) {
            Log.i(TAG, "[$contactName] Initializing session pool with $poolSize sessions (No-Cooking Mode)")
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

            // 减少抖动延迟，加快建立速度
            val jitter = (100..500).random()
            delay(500L + jitter)

            scope.launch {
                try {
                    Log.i(TAG, "[$contactName] Creating WebSocket for session #${sessionIndex}")
                    val webSocket = SesameWebSocket(validToken, character, "RP-Android")

                    if (webSocket.connect()) {
                        var attempts = 0
                        val maxAttempts = 100 // 10秒超时
                        while (!webSocket.isConnected() && attempts < maxAttempts) {
                            delay(100)
                            attempts++
                        }

                        if (webSocket.isConnected()) {
                            val actualLanguage = extractLanguageFromKey(contactName)

                            // [核心修改] 创建即 Ready
                            val sessionState = SessionState(
                                webSocket = webSocket,
                                character = character,
                                contactKey = contactName,
                                language = actualLanguage,
                                createdAt = System.currentTimeMillis(),
                                isPromptComplete = true, // 这一步直接完成
                                promptProgress = 1.0f,
                                job = coroutineContext[Job]!!
                            )

                            sessionPool.offer(sessionState)
                            Log.i(TAG, "[$contactName] Session #${sessionIndex} connected and READY (No Cooking).")

                            // [删除] sendPreRecordedAudioToSession 调用
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

    // [删除] sendPreRecordedAudioToSession 方法已完全移除

    fun getBestAvailableSession(preferredCharacter: String? = null): SessionState? {
        val backendCharacter = getBackendCharacter(contactName)
        val requestedLanguage = extractLanguageFromKey(contactName)

        val availableSessions = sessionPool.filter {
            it.isAvailable && !it.isInUse && it.webSocket.isConnected() &&
                    it.character == backendCharacter && it.contactKey == contactName &&
                    it.language == requestedLanguage
        }

        // 直接取第一个，因为所有 Session 都是 Ready 的
        val bestSession = availableSessions.firstOrNull()

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
        // 在新模式下，这里总是返回 (1.0, true)
        return Pair(1.0f, true)
    }

    fun getAllSessionsProgress(): List<SessionInfo> {
        return emptyList()
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