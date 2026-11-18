package com.o5wtf.detective.speech

import android.content.ComponentName
import android.content.Intent
import android.content.pm.ResolveInfo
import android.content.Context
import android.media.AudioManager
import android.os.SystemClock
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognitionService
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Системный распознаватель Android, тот же движок, что у микрофона Gboard.
 * Все вызовы SpeechRecognizer идут с UI-потока.
 */
class SystemSpeechPlugin(godot: Godot) : GodotPlugin(godot) {
    private var recognizer: SpeechRecognizer? = null
    private var latestPartial: String = ""
    private var acceptResults: Boolean = false
    private var createdOnDevice: Boolean = false
    private var streamsMuted: Boolean = false
    private var rmsMax: Float = 0f
    private var partialCount: Int = 0
    private var lastRawError: Int = -1
    private var lastErrorName: String = ""
    private var finalLength: Int = 0
    private var listenComponent: String = ""
    private var listenOnDevice: Boolean = false
    private var startedAt: Long = 0L
    private var readyAt: Long = 0L
    private var beganAt: Long = 0L
    private var endedAt: Long = 0L
    private var attemptSummary: String = ""

    override fun getPluginName(): String = "SystemSpeech"

    override fun getPluginSignals(): MutableSet<SignalInfo> {
        val signals = mutableSetOf<SignalInfo>()
        signals.add(SignalInfo("partial", String::class.java))
        signals.add(SignalInfo("finished", String::class.java))
        signals.add(SignalInfo("failed", String::class.java))
        return signals
    }

    @UsedByGodot
    fun isAvailable(): Boolean {
        return reportSaysAvailable(readDiagnostics())
    }

    @UsedByGodot
    fun diagnosticsJson(): String = readDiagnostics().toString()

    @UsedByGodot
    fun apiLevel(): Int = Build.VERSION.SDK_INT

    private fun readDiagnostics(): JSONObject {
        val box = arrayOf(JSONObject())
        val ran = runOnUiBlocking { box[0] = buildDiagnostics() }
        if (!ran) {
            return JSONObject()
                .put("sdk_int", Build.VERSION.SDK_INT)
                .put("manufacturer", Build.MANUFACTURER ?: "")
                .put("model", Build.MODEL ?: "")
                .put("activity", "missing")
                .put("is_recognition_available", false)
                .put("is_recognition_available_error", "ui thread timeout")
                .put("on_device_available", false)
                .put("on_device_available_error", "ui thread timeout")
                .put("services", JSONArray())
                .put("services_error", "ui thread timeout")
                .put("voice_recognition_service", "")
                .put("voice_recognition_service_error", "ui thread timeout")
        }
        return box[0]
    }

    private fun buildDiagnostics(): JSONObject {
        val json = JSONObject()
        json.put("sdk_int", Build.VERSION.SDK_INT)
        json.put("manufacturer", Build.MANUFACTURER ?: "")
        json.put("model", Build.MODEL ?: "")
        json.put("thread", if (Looper.myLooper() == Looper.getMainLooper()) "main" else "other")
        val host = activity
        if (host == null) {
            json.put("activity", "missing")
            json.put("is_recognition_available", false)
            json.put("is_recognition_available_error", "activity is null")
            json.put("on_device_available", false)
            json.put("on_device_available_error", "activity is null")
            json.put("services", JSONArray())
            json.put("services_error", "activity is null")
            json.put("voice_recognition_service", "")
            json.put("voice_recognition_service_error", "activity is null")
            return json
        }
        json.put("activity", "present")
        try {
            json.put("is_recognition_available", SpeechRecognizer.isRecognitionAvailable(host))
            json.put("is_recognition_available_error", "")
        } catch (error: Throwable) {
            json.put("is_recognition_available", false)
            json.put("is_recognition_available_error", error.toString())
        }
        if (Build.VERSION.SDK_INT < 31) {
            json.put("on_device_available", false)
            json.put("on_device_available_error", "api<31")
        } else {
            try {
                json.put("on_device_available", SpeechRecognizer.isOnDeviceRecognitionAvailable(host))
                json.put("on_device_available_error", "")
            } catch (error: Throwable) {
                json.put("on_device_available", false)
                json.put("on_device_available_error", error.toString())
            }
        }
        val services = JSONArray()
        try {
            val intent = Intent(RecognitionService.SERVICE_INTERFACE)
            val found: List<ResolveInfo> = host.packageManager.queryIntentServices(intent, 0)
            for (info in found) {
                val service = info.serviceInfo ?: continue
                services.put(JSONObject().put("package", service.packageName).put("class", service.name))
            }
            json.put("services_error", "")
        } catch (error: Throwable) {
            json.put("services_error", error.toString())
        }
        json.put("services", services)
        try {
            val value = Settings.Secure.getString(host.contentResolver, "voice_recognition_service") ?: ""
            json.put("voice_recognition_service", value)
            json.put("voice_recognition_service_error", "")
        } catch (error: Throwable) {
            json.put("voice_recognition_service", "")
            json.put("voice_recognition_service_error", error.toString())
        }
        return json
    }

    private fun reportSaysAvailable(report: JSONObject): Boolean {
        if (report.optBoolean("is_recognition_available", false)) return true
        if (report.optBoolean("on_device_available", false)) return true
        return (report.optJSONArray("services")?.length() ?: 0) > 0
    }

    private fun listedServices(report: JSONObject): List<ComponentName> {
        val names = mutableListOf<ComponentName>()
        val services = report.optJSONArray("services") ?: return names
        for (index in 0 until services.length()) {
            val item = services.optJSONObject(index) ?: continue
            val pkg = item.optString("package", "")
            val cls = item.optString("class", "")
            if (pkg.isNotEmpty() && cls.isNotEmpty()) {
                names.add(ComponentName(pkg, cls))
            }
        }
        return names
    }

    private fun componentFromSecure(raw: String): ComponentName? {
        val text = raw.trim()
        if (text.isEmpty()) return null
        return ComponentName.unflattenFromString(text)
    }

    private fun muteBeeps() {
        val am = audioManager() ?: return
        if (streamsMuted) return
        am.adjustStreamVolume(AudioManager.STREAM_NOTIFICATION, AudioManager.ADJUST_MUTE, 0)
        am.adjustStreamVolume(AudioManager.STREAM_SYSTEM, AudioManager.ADJUST_MUTE, 0)
        streamsMuted = true
    }

    private fun restoreBeeps() {
        val am = audioManager() ?: return
        if (!streamsMuted) return
        am.adjustStreamVolume(AudioManager.STREAM_NOTIFICATION, AudioManager.ADJUST_UNMUTE, 0)
        am.adjustStreamVolume(AudioManager.STREAM_SYSTEM, AudioManager.ADJUST_UNMUTE, 0)
        streamsMuted = false
    }

    private fun audioManager(): AudioManager? {
        val host = activity ?: return null
        return host.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    }

    private fun resetAttempt(component: String, onDevice: Boolean) {
        rmsMax = 0f
        partialCount = 0
        lastRawError = -1
        lastErrorName = ""
        finalLength = 0
        listenComponent = component
        listenOnDevice = onDevice
        readyAt = 0L
        beganAt = 0L
        endedAt = 0L
        startedAt = SystemClock.elapsedRealtime()
        attemptSummary = ""
    }

    private fun writeAttempt() {
        val origin = if (startedAt == 0L) SystemClock.elapsedRealtime() else startedAt
        fun rel(at: Long): String = if (at == 0L) "-" else (at - origin).toString()
        attemptSummary = "listen component=%s on_device=%s ready=%s begin=%s rms_max=%.1f end=%s partials=%d final_len=%d error=%s:%s".format(
            listenComponent.ifEmpty { "-" },
            if (listenOnDevice) "yes" else "no",
            rel(readyAt),
            rel(beganAt),
            rmsMax,
            rel(endedAt),
            partialCount,
            finalLength,
            if (lastRawError < 0) "-" else lastRawError.toString(),
            lastErrorName.ifEmpty { "-" },
        )
    }

    private fun preferGoogle(services: List<ComponentName>): ComponentName? {
        return services.firstOrNull {
            it.packageName.contains("googlequicksearchbox") || it.packageName.startsWith("com.google.")
        } ?: services.firstOrNull()
    }

    private fun runOnUiBlocking(block: () -> Unit): Boolean {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
            return true
        }
        val finished = AtomicBoolean(false)
        val latch = CountDownLatch(1)
        runOnUiThread {
            try {
                block()
                finished.set(true)
            } finally {
                latch.countDown()
            }
        }
        val waited = latch.await(3, TimeUnit.SECONDS)
        return waited && finished.get()
    }

    override fun onMainDestroy() {
        runOnUiThread {
            acceptResults = false
            latestPartial = ""
            recognizer?.destroy()
            recognizer = null
            restoreBeeps()
        }
        super.onMainDestroy()
    }

    @UsedByGodot
    fun startListening(preferOffline: Boolean) {
        runOnUiThread {
            val host = activity ?: run {
                emitSignal("failed", "unavailable")
                return@runOnUiThread
            }
            val report = buildDiagnostics()
            if (!reportSaysAvailable(report)) {
                lastErrorName = "unavailable"
                writeAttempt()
                emitSignal("failed", "unavailable")
                return@runOnUiThread
            }
            acceptResults = true
            latestPartial = ""
            val onDevice = report.optBoolean("on_device_available", false)
            val services = listedServices(report)
            val useOnDevice = preferOffline && onDevice
            val chosen = if (useOnDevice) null else componentFromSecure(report.optString("voice_recognition_service")) ?: preferGoogle(services)
            recognizer?.destroy()
            recognizer = null
            resetAttempt(chosen?.flattenToString() ?: if (useOnDevice) "on-device" else "-", useOnDevice)
            try {
                muteBeeps()
                recognizer = if (useOnDevice) {
                    SpeechRecognizer.createOnDeviceSpeechRecognizer(host)
                } else if (chosen != null) {
                    SpeechRecognizer.createSpeechRecognizer(host, chosen)
                } else {
                    SpeechRecognizer.createSpeechRecognizer(host)
                }
                createdOnDevice = useOnDevice
                recognizer?.setRecognitionListener(listener)
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
                intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                intent.putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, host.packageName)
                intent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 60000)
                intent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 10000)
                intent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 8000)
                if (preferOffline) {
                    intent.putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                }
                recognizer?.startListening(intent)
            } catch (error: Throwable) {
                restoreBeeps()
                lastRawError = -1
                lastErrorName = "client"
                writeAttempt()
                emitSignal("failed", "client")
            }
        }
    }

    @UsedByGodot
    fun stopListening() {
        runOnUiThread { recognizer?.stopListening() }
    }

    @UsedByGodot
    fun cancelListening() {
        runOnUiThread {
            acceptResults = false
            latestPartial = ""
            recognizer?.cancel()
            restoreBeeps()
        }
    }

    @UsedByGodot
    fun partialText(): String = latestPartial

    @UsedByGodot
    fun rmsUnit(): Float {
        val scaled = (rmsMax + 2f) / 12f
        return scaled.coerceIn(0f, 1f)
    }

    @UsedByGodot
    fun attemptLog(): String = attemptSummary

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            readyAt = SystemClock.elapsedRealtime()
        }
        override fun onBeginningOfSpeech() {
            beganAt = SystemClock.elapsedRealtime()
        }
        override fun onRmsChanged(rmsdB: Float) {
            if (rmsdB > rmsMax) rmsMax = rmsdB
        }
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {
            endedAt = SystemClock.elapsedRealtime()
            restoreBeeps()
        }
        override fun onError(error: Int) {
            if (!acceptResults) {
                restoreBeeps()
                return
            }
            lastRawError = error
            lastErrorName = codeName(error)
            writeAttempt()
            restoreBeeps()
            emitSignal("failed", lastErrorName)
        }
        override fun onResults(results: Bundle?) {
            if (!acceptResults) {
                restoreBeeps()
                return
            }
            val lines = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val text = lines?.firstOrNull() ?: ""
            finalLength = text.length
            if (endedAt == 0L) endedAt = SystemClock.elapsedRealtime()
            writeAttempt()
            restoreBeeps()
            emitSignal("finished", text)
        }
        override fun onPartialResults(partialResults: Bundle?) {
            if (!acceptResults) {
                return
            }
            val lines = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val text = lines?.firstOrNull() ?: ""
            if (text.isNotEmpty()) {
                partialCount += 1
                latestPartial = text
                emitSignal("partial", text)
            }
        }
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun codeName(error: Int): String {
        return when (error) {
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "network_timeout"
            SpeechRecognizer.ERROR_NETWORK -> "network"
            SpeechRecognizer.ERROR_AUDIO -> "audio"
            SpeechRecognizer.ERROR_SERVER -> "server"
            SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "server_disconnected"
            SpeechRecognizer.ERROR_CLIENT -> "client"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "speech_timeout"
            SpeechRecognizer.ERROR_NO_MATCH -> "no_match"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permissions"
            SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> "too_many_requests"
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "language_not_supported"
            SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "language_unavailable"
            SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT -> "cannot_check"
            15 -> "cannot_listen_to_download_events"
            else -> "unavailable"
        }
    }
}
