package com.o5wtf.detective.speech

import android.content.Intent
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
        val host = activity ?: return false
        return SpeechRecognizer.isRecognitionAvailable(host)
    }

    @UsedByGodot
    fun startListening(preferOffline: Boolean) {
        runOnUiThread {
            val host = activity ?: run {
                emitSignal("failed", "unavailable")
                return@runOnUiThread
            }
            if (!SpeechRecognizer.isRecognitionAvailable(host)) {
                emitSignal("failed", "unavailable")
                return@runOnUiThread
            }
            if (recognizer == null) {
                recognizer = SpeechRecognizer.createSpeechRecognizer(host)
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
        runOnUiThread { recognizer?.cancel() }
    }

    @UsedByGodot
    fun partialText(): String = ""

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onError(error: Int) {
            emitSignal("failed", codeName(error))
        }
        override fun onResults(results: Bundle?) {
            val lines = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            emitSignal("finished", lines?.firstOrNull() ?: "")
        }
        override fun onPartialResults(partialResults: Bundle?) {
            val lines = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val text = lines?.firstOrNull() ?: ""
            if (text.isNotEmpty()) {
                emitSignal("partial", text)
            }
        }
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun codeName(error: Int): String {
        return when (error) {
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_NETWORK -> "network"
            SpeechRecognizer.ERROR_NO_MATCH -> "no_match"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permissions"
            else -> "unavailable"
        }
    }
}
