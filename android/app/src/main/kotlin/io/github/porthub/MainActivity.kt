package io.github.porthub

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.hardware.input.InputManager
import android.net.Uri
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.GLES20
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.Settings
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.flame_engine.gamepads_android.GamepadsCompatibleActivity
import java.io.File
import kotlin.concurrent.thread

/**
 * Activity principal do PortHub.
 *
 * - Implementa [GamepadsCompatibleActivity] para o plugin `gamepads` receber
 *   eventos de controles (Xbox, DualSense, DualShock, Bluetooth genérico).
 * - Expõe o canal `porthub/native` com: análise de hardware, instalação de
 *   APK / APK dividido (PackageInstaller), abrir/desinstalar apps, lista de
 *   apps instalados, notificações e serviço de downloads em segundo plano.
 * - Arquivos de emuladores (ISOs): seletor, leitura parcial e abertura do
 *   jogo no emulador — ver [RomFiles].
 */
class MainActivity : FlutterActivity(), GamepadsCompatibleActivity {
    private var keyListener: ((KeyEvent) -> Boolean)? = null
    private var motionListener: ((MotionEvent) -> Boolean)? = null
    private val main = Handler(Looper.getMainLooper())

    /** Instalações aguardando resultado: sessionId → resposta para o Dart. */
    private val pendingInstalls = mutableMapOf<Int, MethodChannel.Result>()
    private var receiverRegistered = false
    private val roms by lazy { RomFiles(this) }

    companion object {
        private const val CHANNEL = "porthub/native"
        private const val ACTION_INSTALL_STATUS = "io.github.porthub.INSTALL_STATUS"
        const val CHANNEL_UPDATES = "porthub_updates"
    }

    // ---------------------------------------------------------------- gamepads
    override fun dispatchGenericMotionEvent(motionEvent: MotionEvent): Boolean {
        if (motionListener?.invoke(motionEvent) == true) return true
        return super.dispatchGenericMotionEvent(motionEvent)
    }

    override fun dispatchKeyEvent(keyEvent: KeyEvent): Boolean {
        if (keyListener?.invoke(keyEvent) == true) return true
        return super.dispatchKeyEvent(keyEvent)
    }

    override fun registerInputDeviceListener(listener: InputManager.InputDeviceListener, handler: Handler?) {
        (getSystemService(INPUT_SERVICE) as InputManager).registerInputDeviceListener(listener, null)
    }

    override fun registerKeyEventHandler(handler: (KeyEvent) -> Boolean) {
        keyListener = handler
    }

    override fun registerMotionEventHandler(handler: (MotionEvent) -> Boolean) {
        motionListener = handler
    }

    // ------------------------------------------------------------------ canal
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error("native_error", e.message, null)
            }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getHardwareInfo" -> thread {
                val info = hardwareInfo()
                main.post { result.success(info) }
            }
            "installApks" -> installApks(call.argument<List<String>>("paths") ?: emptyList(), result)
            "canRequestPackageInstalls" -> result.success(
                Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
            )
            "openInstallPermissionSettings" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                }
                result.success(null)
            }
            "getApkInfo" -> {
                val info = packageManager.getPackageArchiveInfo(call.argument<String>("path")!!, 0)
                result.success(info?.let { mapOf("package" to it.packageName, "version" to it.versionName) })
            }
            "getInstalledVersion" -> result.success(installedVersion(call.argument<String>("package")!!))
            "launchPackage" -> {
                val pkg = call.argument<String>("package")!!
                val intent = packageManager.getLaunchIntentForPackage(pkg)
                    ?: packageManager.getLeanbackLaunchIntentForPackage(pkg)
                if (intent == null) {
                    result.success(false)
                } else {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }
            }
            "uninstallPackage" -> {
                startActivity(Intent(Intent.ACTION_DELETE, Uri.parse("package:${call.argument<String>("package")}")))
                result.success(null)
            }
            "listInstalledPackages" -> thread {
                val list = installedPackages()
                main.post { result.success(list) }
            }
            "downloadService" -> {
                val running = call.argument<Boolean>("running") ?: false
                val intent = Intent(this, DownloadService::class.java)
                if (running) {
                    intent.putExtra(DownloadService.EXTRA_TEXT, call.argument<String>("text") ?: "")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                } else {
                    stopService(intent)
                }
                result.success(null)
            }
            "notify" -> {
                notify(call.argument<String>("title") ?: "", call.argument<String>("body") ?: "", call.argument<Int>("id") ?: 1)
                result.success(null)
            }
            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT >= 33 &&
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                ) {
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 42)
                }
                result.success(null)
            }
            "pickRomFiles" -> roms.pickFiles(result)
            "pickRomFolder" -> roms.pickFolder(call.argument<List<String>>("extensions") ?: emptyList(), result)
            "readUri" -> {
                val uri = call.argument<String>("uri")!!
                val offset = (call.argument<Number>("offset") ?: 0).toLong()
                val length = call.argument<Int>("length") ?: 0
                thread {
                    try {
                        val bytes = roms.read(uri, offset, length)
                        main.post { result.success(bytes) }
                    } catch (e: Exception) {
                        main.post { result.error("read_failed", e.message, null) }
                    }
                }
            }
            "uriSize" -> thread {
                val size = try { roms.size(call.argument<String>("uri")!!) } catch (_: Exception) { null }
                main.post { result.success(size) }
            }
            "canReadUri" -> result.success(roms.canRead(call.argument<String>("uri")!!))
            "releaseUri" -> {
                roms.release(call.argument<String>("uri")!!)
                result.success(null)
            }
            "launchEmulatorGame" -> result.success(
                roms.launch(
                    this,
                    call.argument<String>("package")!!,
                    call.argument<String>("activity")!!,
                    call.argument<String>("uri")!!,
                    call.argument<String>("action") ?: Intent.ACTION_VIEW,
                )
            )
            else -> result.notImplemented()
        }
    }

    @Deprecated("FlutterActivity não é ComponentActivity; resultado do seletor do SAF")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!roms.onActivityResult(requestCode, resultCode, data)) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    // ------------------------------------------------------------- hardware
    private fun hardwareInfo(): Map<String, Any?> {
        val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        val mem = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val stat = StatFs(filesDir.absolutePath)
        val metrics = resources.displayMetrics
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else @Suppress("DEPRECATION") windowManager.defaultDisplay
        val refresh = display?.let { d ->
            val modes = d.supportedModes.map { it.refreshRate }
            (modes.maxOrNull() ?: d.refreshRate).toDouble()
        }
        val realSize = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = windowManager.maximumWindowMetrics.bounds
            Pair(b.width(), b.height())
        } else {
            Pair(metrics.widthPixels, metrics.heightPixels)
        }
        val gl = queryGl()
        val glEs = am.deviceConfigurationInfo.reqGlEsVersion
        val glEsVersion = "${glEs shr 16}.${glEs and 0xffff}".toDouble()

        return mapOf(
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "release" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "kernel" to System.getProperty("os.version"),
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "ramMb" to (mem.totalMem / (1024 * 1024)).toInt(),
            "cores" to Runtime.getRuntime().availableProcessors(),
            "maxFreqMhz" to maxCpuFreqMhz(),
            "cpuName" to cpuName(),
            "socModel" to (if (Build.VERSION.SDK_INT >= 31) Build.SOC_MODEL.takeIf { it != Build.UNKNOWN } else null),
            "gpuRenderer" to gl["renderer"],
            "gpuVendor" to gl["vendor"],
            "gpuVersion" to gl["version"],
            "glEsVersion" to glEsVersion,
            "vulkan" to (vulkanVersion() != null),
            "vulkanVersion" to vulkanVersion(),
            "freeStorageMb" to (stat.availableBytes / (1024 * 1024)).toInt(),
            "totalStorageMb" to (stat.totalBytes / (1024 * 1024)).toInt(),
            "screenWidth" to realSize.first,
            "screenHeight" to realSize.second,
            "refreshRate" to refresh,
        )
    }

    /** Nome comercial do SoC (ex.: "Qualcomm Snapdragon 778G" via ro.soc / /proc/cpuinfo). */
    private fun cpuName(): String? {
        if (Build.VERSION.SDK_INT >= 31) {
            val mfr = Build.SOC_MANUFACTURER.takeIf { it != Build.UNKNOWN }
            val model = Build.SOC_MODEL.takeIf { it != Build.UNKNOWN }
            if (model != null) return listOfNotNull(mfr, model).joinToString(" ")
        }
        return try {
            File("/proc/cpuinfo").readLines()
                .firstOrNull { it.startsWith("Hardware") || it.startsWith("model name") }
                ?.substringAfter(":")?.trim()
                ?: Build.HARDWARE
        } catch (_: Exception) {
            Build.HARDWARE
        }
    }

    private fun maxCpuFreqMhz(): Int? = try {
        File("/sys/devices/system/cpu").listFiles { f -> f.name.matches(Regex("cpu\\d+")) }
            ?.mapNotNull { File(it, "cpufreq/cpuinfo_max_freq").takeIf { f -> f.exists() }?.readText()?.trim()?.toIntOrNull() }
            ?.maxOrNull()?.div(1000)
    } catch (_: Exception) {
        null
    }

    /** Maior versão de Vulkan declarada pelo sistema (1.0 – 1.4). */
    private fun vulkanVersion(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return null
        val versions = listOf(0x404000 to "1.4", 0x403000 to "1.3", 0x402000 to "1.2", 0x401000 to "1.1", 0x400000 to "1.0")
        for ((code, name) in versions) {
            if (packageManager.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, code)) return name
        }
        return null
    }

    /** Cria um contexto EGL invisível só para ler GL_RENDERER / GL_VENDOR / GL_VERSION. */
    private fun queryGl(): Map<String, String?> {
        val out = mutableMapOf<String, String?>()
        try {
            val dpy = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            val ver = IntArray(2)
            EGL14.eglInitialize(dpy, ver, 0, ver, 1)
            val attribs = intArrayOf(EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT, EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT, EGL14.EGL_NONE)
            val configs = arrayOfNulls<EGLConfig>(1)
            val num = IntArray(1)
            EGL14.eglChooseConfig(dpy, attribs, 0, configs, 0, 1, num, 0)
            val ctx = EGL14.eglCreateContext(dpy, configs[0], EGL14.EGL_NO_CONTEXT, intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0)
            val surf = EGL14.eglCreatePbufferSurface(dpy, configs[0], intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE), 0)
            EGL14.eglMakeCurrent(dpy, surf, surf, ctx)
            out["renderer"] = GLES20.glGetString(GLES20.GL_RENDERER)
            out["vendor"] = GLES20.glGetString(GLES20.GL_VENDOR)
            out["version"] = GLES20.glGetString(GLES20.GL_VERSION)
            EGL14.eglMakeCurrent(dpy, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            EGL14.eglDestroySurface(dpy, surf)
            EGL14.eglDestroyContext(dpy, ctx)
            EGL14.eglTerminate(dpy)
        } catch (_: Exception) {
        }
        return out
    }

    // ----------------------------------------------------------- instalação
    private fun installApks(paths: List<String>, result: MethodChannel.Result) {
        if (paths.isEmpty()) {
            result.success(mapOf("success" to false, "message" to "Nenhum APK"))
            return
        }
        ensureInstallReceiver()
        thread {
            try {
                val installer = packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                if (Build.VERSION.SDK_INT >= 31) params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
                val sessionId = installer.createSession(params)
                installer.openSession(sessionId).use { session ->
                    // Vários APKs na mesma sessão = instalação de APK dividido (base + splits).
                    paths.forEachIndexed { i, p ->
                        val f = File(p)
                        f.inputStream().use { input ->
                            session.openWrite("apk_$i", 0, f.length()).use { out ->
                                input.copyTo(out, 1 shl 16)
                                session.fsync(out)
                            }
                        }
                    }
                    main.post { pendingInstalls[sessionId] = result }
                    val intent = Intent(ACTION_INSTALL_STATUS).setPackage(packageName)
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                    val pi = PendingIntent.getBroadcast(this, sessionId, intent, flags)
                    session.commit(pi.intentSender)
                }
            } catch (e: Exception) {
                main.post { result.success(mapOf("success" to false, "message" to (e.message ?: "Falha na instalação"))) }
            }
        }
    }

    private val installReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val sessionId = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
            when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    @Suppress("DEPRECATION")
                    val confirm = if (Build.VERSION.SDK_INT >= 33) {
                        intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                    } else {
                        intent.getParcelableExtra(Intent.EXTRA_INTENT)
                    }
                    confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    if (confirm != null) startActivity(confirm)
                }
                PackageInstaller.STATUS_SUCCESS -> pendingInstalls.remove(sessionId)?.success(mapOf("success" to true))
                else -> {
                    val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "Falha ($status)"
                    pendingInstalls.remove(sessionId)?.success(mapOf("success" to false, "message" to msg))
                }
            }
        }
    }

    private fun ensureInstallReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter(ACTION_INSTALL_STATUS)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(installReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(installReceiver, filter)
        }
        receiverRegistered = true
    }

    override fun onDestroy() {
        if (receiverRegistered) unregisterReceiver(installReceiver)
        super.onDestroy()
    }

    private fun installedVersion(pkg: String): String? = try {
        packageManager.getPackageInfo(pkg, 0).versionName ?: "?"
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    private fun installedPackages(): List<Map<String, Any?>> =
        packageManager.getInstalledPackages(0)
            .filter { (it.applicationInfo?.flags ?: ApplicationInfo.FLAG_SYSTEM) and ApplicationInfo.FLAG_SYSTEM == 0 }
            .map {
                mapOf(
                    "package" to it.packageName,
                    "label" to it.applicationInfo?.loadLabel(packageManager)?.toString(),
                    "version" to it.versionName,
                )
            }

    // --------------------------------------------------------- notificações
    private fun notify(title: String, body: String, id: Int) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL_UPDATES, "Atualizações e instalações", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(this, CHANNEL_UPDATES)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try {
            nm.notify(id, n)
        } catch (_: SecurityException) {
            // Permissão de notificação negada.
        }
    }
}
