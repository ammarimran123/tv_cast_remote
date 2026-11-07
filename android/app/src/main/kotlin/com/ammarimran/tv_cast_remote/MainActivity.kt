package com.ammarimran.tv_cast_remote

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque

class MainActivity : FlutterActivity() {
    companion object {
        private const val MIC_REQUEST = 7301
    }

    private val main = Handler(Looper.getMainLooper())
    private var nsd: NsdManager? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var events: EventChannel.EventSink? = null
    private val listeners = mutableListOf<NsdManager.DiscoveryListener>()
    private val resolveQueue = ArrayDeque<NsdServiceInfo>()
    private var resolving = false

    private var recorder: AudioRecord? = null
    private var micSink: EventChannel.EventSink? = null
    private var pendingMicPermission: MethodChannel.Result? = null

    private val serviceTypes = listOf("_androidtvremote2._tcp.", "_googlecast._tcp.")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "tvcast/discovery").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    events = sink
                }

                override fun onCancel(arguments: Any?) {
                    events = null
                }
            })

        EventChannel(messenger, "tvcast/mic").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    micSink = sink
                }

                override fun onCancel(arguments: Any?) {
                    micSink = null
                }
            })

        MethodChannel(messenger, "tvcast/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "micPermission" -> {
                    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                        PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        pendingMicPermission?.success(false)
                        pendingMicPermission = result
                        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MIC_REQUEST)
                    }
                }
                "startMic" -> result.success(startMic())
                "stopMic" -> {
                    stopMic(); result.success(null)
                }
                "startDiscovery" -> {
                    startDiscovery(); result.success(null)
                }
                "stopDiscovery" -> {
                    stopDiscovery(); result.success(null)
                }
                "openScreenCast" -> result.success(openScreenCast())
                "openGoogleHome" -> result.success(openGoogleHome())
                else -> result.notImplemented()
            }
        }
    }

    // ---------------- mDNS discovery ----------------

    private fun startDiscovery() {
        stopDiscovery()
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifi.createMulticastLock("tvcast-discovery").apply {
            setReferenceCounted(false)
            acquire()
        }
        val manager = getSystemService(Context.NSD_SERVICE) as NsdManager
        nsd = manager
        for (type in serviceTypes) {
            val listener = object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(serviceType: String) {}
                override fun onDiscoveryStopped(serviceType: String) {}
                override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
                override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
                override fun onServiceLost(info: NsdServiceInfo) {}
                override fun onServiceFound(info: NsdServiceInfo) {
                    main.post {
                        resolveQueue.add(info)
                        resolveNext()
                    }
                }
            }
            try {
                manager.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener)
                listeners.add(listener)
            } catch (_: Exception) {
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun resolveNext() {
        val manager = nsd ?: return
        if (resolving) return
        val info = resolveQueue.pollFirst() ?: return
        resolving = true
        try {
            manager.resolveService(info, object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    main.post {
                        resolving = false
                        resolveNext()
                    }
                }

                override fun onServiceResolved(resolved: NsdServiceInfo) {
                    val host = resolved.host?.hostAddress
                    val attrs = HashMap<String, String>()
                    try {
                        for ((k, v) in resolved.attributes) {
                            attrs[k] = v?.let { String(it, Charsets.UTF_8) } ?: ""
                        }
                    } catch (_: Exception) {
                    }
                    val event = hashMapOf<String, Any?>(
                        "type" to resolved.serviceType,
                        "name" to resolved.serviceName,
                        "host" to host,
                        "port" to resolved.port,
                        "attrs" to attrs,
                    )
                    main.post {
                        events?.success(event)
                        resolving = false
                        resolveNext()
                    }
                }
            })
        } catch (_: Exception) {
            resolving = false
            main.post { resolveNext() }
        }
    }

    private fun stopDiscovery() {
        val manager = nsd
        for (l in listeners) {
            try {
                manager?.stopServiceDiscovery(l)
            } catch (_: Exception) {
            }
        }
        listeners.clear()
        resolveQueue.clear()
        resolving = false
        try {
            multicastLock?.release()
        } catch (_: Exception) {
        }
        multicastLock = null
    }

    // ---------------- Screen mirroring ----------------

    private fun tryStart(intent: Intent): Boolean {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    /** Opens the system Cast-screen picker (Google Cast mirroring). */
    private fun openScreenCast(): String? {
        if (tryStart(Intent("android.settings.CAST_SETTINGS"))) return "cast"
        packageManager.getLaunchIntentForPackage("com.samsung.android.smartmirroring")?.let {
            if (tryStart(it)) return "smart_view"
        }
        if (tryStart(Intent("android.settings.WIFI_DISPLAY_SETTINGS"))) return "wifi_display"
        if (tryStart(Intent().setComponent(ComponentName(
                "com.android.settings", "com.android.settings.Settings\$WifiDisplaySettingsActivity")))) {
            return "wifi_display"
        }
        if (openGoogleHome()) return "google_home"
        return null
    }

    private fun openGoogleHome(): Boolean {
        val pkg = "com.google.android.apps.chromecast.app"
        packageManager.getLaunchIntentForPackage(pkg)?.let { if (tryStart(it)) return true }
        return tryStart(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$pkg"))) ||
            tryStart(Intent(Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=$pkg")))
    }

    // ---------------- Microphone (voice search) ----------------

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == MIC_REQUEST) {
            pendingMicPermission?.success(
                grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingMicPermission = null
        }
    }

    /** Records 16-bit mono PCM at 8 kHz (what Android TV voice search expects)
     *  and streams 8 KB chunks (512 ms) to Dart. */
    private fun startMic(): Boolean {
        stopMic()
        val rate = 8000
        val minBuf = AudioRecord.getMinBufferSize(
            rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minBuf <= 0) return false
        val rec = try {
            AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, rate,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                maxOf(minBuf, 16384))
        } catch (_: Exception) {
            return false
        }
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            return false
        }
        recorder = rec
        rec.startRecording()
        Thread {
            val buf = ByteArray(8192)
            while (recorder === rec) {
                var off = 0
                while (off < buf.size && recorder === rec) {
                    val n = rec.read(buf, off, buf.size - off)
                    if (n <= 0) break
                    off += n
                }
                if (off > 0) {
                    val chunk = buf.copyOf(off)
                    main.post { micSink?.success(chunk) }
                }
            }
            try {
                rec.stop()
            } catch (_: Exception) {
            }
            rec.release()
        }.start()
        return true
    }

    private fun stopMic() {
        recorder = null // the recording thread notices and releases it
    }

    override fun onDestroy() {
        stopMic()
        stopDiscovery()
        super.onDestroy()
    }
}
