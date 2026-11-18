package com.o5wtf.detective.speech

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Системный распознаватель Android, тот же движок, что у микрофона Gboard.
 * Все вызовы SpeechRecognizer идут с UI-потока.
 */
class SystemSpeechPlugin(godot: Godot) : GodotPlugin(godot) {
    private var recognizer: SpeechRecognizer? = null
    private var latestPartial: String = ""
    private var acceptResults: Boolean = false
    private var createdOnDevice: Boolean = false

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
        return recognitionServiceAvailable() || onDeviceAvailable()
    }

    @UsedByGodot
    fun recognitionServiceAvailable(): Boolean {
        val host = activity ?: return false
        return SpeechRecognizer.isRecognitionAvailable(host)
    }

    @UsedByGodot
    fun onDeviceAvailable(): Boolean {
        val host = activity ?: return false
        if (Build.VERSION.SDK_INT < 31) {
            return false
        }
        return SpeechRecognizer.isOnDeviceRecognitionAvailable(host)
    }

    @UsedByGodot
    fun apiLevel(): Int = Build.VERSION.SDK_INT

    override fun onMainDestroy() {
        runOnUiThread {
            acceptResults = false
            latestPartial = ""
            recognizer?.destroy()
            recognizer = null
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
            if (!isAvailable()) {
                emitSignal("failed", "unavailable")
                return@runOnUiThread
            }
            acceptResults = true
            latestPartial = ""
            val useOnDevice = onDeviceAvailable() && (preferOffline || !recognitionServiceAvailable())
            if (recognizer != null && createdOnDevice != useOnDevice) {
                recognizer?.destroy()
                recognizer = null
            }
            if (recognizer == null) {
                recognizer = if (useOnDevice) {
                    SpeechRecognizer.createOnDeviceSpeechRecognizer(host)
                } else {
                    SpeechRecognizer.createSpeechRecognizer(host)
                }
                createdOnDevice = useOnDevice
                recognizer?.setRecognitionListener(listener)
            }
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
            intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            intent.putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, host.packageName)
            if (preferOffline) {
                intent.putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            }
            recognizer?.startListening(intent)
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
        }
    }

    @UsedByGodot
    fun partialText(): String = latestPartial

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onError(error: Int) {
            if (!acceptResults) {
                return
            }
            emitSignal("failed", codeName(error))
        }
        override fun onResults(results: Bundle?) {
            if (!acceptResults) {
                return
            }
            val lines = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            emitSignal("finished", lines?.firstOrNull() ?: "")
        }
        override fun onPartialResults(partialResults: Bundle?) {
            if (!acceptResults) {
                return
            }
            val lines = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val text = lines?.firstOrNull() ?: ""
            if (text.isNotEmpty()) {
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
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "language_not_supported"
            SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "language_unavailable"
            SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT -> "cannot_check"
            SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> "too_many_requests"
            else -> "unavailable"
        }
    }
}
