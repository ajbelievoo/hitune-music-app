package com.hitune.app

import android.media.audiofx.BassBoost
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Virtualizer
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    private var audioFxChannel: MethodChannel? = null
    private val sessionFx = AudioSessionFx()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioFxChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hitune/audio_fx")
        audioFxChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "attach" -> {
                        val sessionId = call.argument<Int>("sessionId") ?: 0
                        sessionFx.attach(sessionId)
                        result.success(null)
                    }
                    "setBass" -> {
                        sessionFx.setBass(
                            call.argument<Boolean>("enabled") ?: false,
                            (call.argument<Int>("strength") ?: 0).toShort(),
                        )
                        result.success(null)
                    }
                    "setSurround" -> {
                        sessionFx.setSurround(
                            call.argument<Boolean>("enabled") ?: false,
                            (call.argument<Int>("strength") ?: 0).toShort(),
                        )
                        result.success(null)
                    }
                    "setCompressor" -> {
                        sessionFx.setCompressor(
                            call.argument<Boolean>("enabled") ?: false,
                            (call.argument<Double>("amount") ?: 0.0).toFloat(),
                        )
                        result.success(null)
                    }
                    "release" -> {
                        sessionFx.release()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("audio_fx", e.message, null)
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        sessionFx.release()
        audioFxChannel?.setMethodCallHandler(null)
        audioFxChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

/// Session-attached audio effects that just_audio does not expose:
/// bass boost, stereo widening (virtualizer) and a real dynamics processor
/// (multi-band compressor + limiter) for the Spotify-style "punchy" sound.
private class AudioSessionFx {

    private var sessionId = 0
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var dynamics: DynamicsProcessing? = null

    private var bassEnabled = false
    private var bassStrength: Short = 0
    private var surroundEnabled = false
    private var surroundStrength: Short = 0
    private var compressorEnabled = false
    private var compressorAmount = 0f

    @Synchronized
    fun attach(newSessionId: Int) {
        if (newSessionId <= 0) return
        if (newSessionId == sessionId && bassBoost != null) return
        release()
        sessionId = newSessionId
        bassBoost = runCatching { BassBoost(0, sessionId) }.getOrNull()
        virtualizer = runCatching { Virtualizer(0, sessionId) }.getOrNull()
        dynamics = buildDynamicsProcessing(sessionId)
        applyAll()
    }

    @Synchronized
    fun setBass(enabled: Boolean, strength: Short) {
        bassEnabled = enabled
        bassStrength = strength.coerceIn(0, 1000)
        applyBass()
    }

    @Synchronized
    fun setSurround(enabled: Boolean, strength: Short) {
        surroundEnabled = enabled
        surroundStrength = strength.coerceIn(0, 1000)
        applySurround()
    }

    @Synchronized
    fun setCompressor(enabled: Boolean, amount: Float) {
        compressorEnabled = enabled
        compressorAmount = amount.coerceIn(0f, 1f)
        applyCompressor()
    }

    @Synchronized
    fun release() {
        runCatching { bassBoost?.release() }
        runCatching { virtualizer?.release() }
        runCatching { dynamics?.release() }
        bassBoost = null
        virtualizer = null
        dynamics = null
        sessionId = 0
    }

    private fun applyAll() {
        applyBass()
        applySurround()
        applyCompressor()
    }

    private fun applyBass() {
        val fx = bassBoost ?: return
        runCatching {
            if (fx.strengthSupported) {
                fx.setStrength(bassStrength)
            }
            fx.enabled = bassEnabled
        }
    }

    private fun applySurround() {
        val fx = virtualizer ?: return
        runCatching {
            if (fx.strengthSupported) {
                fx.setStrength(surroundStrength)
            }
            fx.enabled = surroundEnabled
        }
    }

    private fun applyCompressor() {
        val dp = dynamics ?: return
        runCatching {
            if (compressorEnabled) {
                runCatching { dp.setMbcBandAllChannelsTo(0, compressorBand(compressorAmount)) }
                runCatching { dp.setLimiterAllChannelsTo(limiter()) }
            }
            dp.enabled = compressorEnabled
        }
    }

    private fun buildDynamicsProcessing(session: Int): DynamicsProcessing? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        return runCatching {
            val mbc = DynamicsProcessing.Mbc(true, true, 1)
            mbc.setBand(0, compressorBand(compressorAmount))

            val preEq = DynamicsProcessing.Eq(true, false, 1)
            preEq.setBand(0, DynamicsProcessing.EqBand(true, 200f, 0f))

            val builder = DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                CHANNELS,
                true, 1,   // pre-EQ in use, 1 band
                true, 1,   // MBC in use, 1 band
                false, 0,  // no post-EQ
                true,      // limiter in use
            )
            builder.setMbcAllChannelsTo(mbc)
            builder.setPreEqAllChannelsTo(preEq)
            builder.setLimiterAllChannelsTo(limiter())

            DynamicsProcessing(0, session, builder.build())
        }.getOrNull()
    }

    /// Map a 0..1 amount to a single-band compressor curve.
    private fun compressorBand(amount: Float): DynamicsProcessing.MbcBand {
        val a = amount.coerceIn(0f, 1f)
        return DynamicsProcessing.MbcBand(
            true,           // enabled
            20000f,         // cutoff: covers the whole spectrum for 1-band MBC
            5f + 10f * a,   // attack time (ms)
            120f,           // release time (ms)
            1.5f + 8.5f * a,// ratio 1.5:1 .. 10:1
            -8f - 24f * a,  // threshold -8 .. -32 dB
            6f,             // knee width (dB)
            -80f,           // noise gate threshold
            1f,             // expander ratio
            0f,             // pre-gain (dB)
            9f * a,         // post-gain makeup (dB)
        )
    }

    private fun limiter(): DynamicsProcessing.Limiter {
        return DynamicsProcessing.Limiter(
            true,   // inUse
            true,   // enabled
            0,      // linkGroup
            1f,     // attack ms
            80f,    // release ms
            10f,    // ratio
            -1f,    // threshold (dB ceiling)
            0f,     // post gain
        )
    }

    private companion object {
        const val CHANNELS = 2
    }
}
