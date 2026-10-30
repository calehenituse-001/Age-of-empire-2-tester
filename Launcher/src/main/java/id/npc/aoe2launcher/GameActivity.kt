package id.npc.aoe2launcher
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotActivity
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

class GameActivity: GodotActivity() {
    override fun getCommandLine(): MutableList<String> = super.getCommandLine().toMutableList().apply {
        addAll(listOf("--main-pack","res://game.pck","--rendering-method","gl_compatibility","--rendering-driver","opengl3","--log-file",Storage(this@GameActivity).file("Logs/godot.log").absolutePath))
    }
    override fun getHostPlugins(engine: Godot): Set<GodotPlugin> = setOf(LauncherBridge(engine,this))
}
class LauncherBridge(engine: Godot,private val host: GameActivity): GodotPlugin(engine) {
    override fun getPluginName()="LauncherBridge"
    @UsedByGodot fun rootPath(): String=Storage(host).root.absolutePath
    @UsedByGodot fun safeMode(): Boolean=host.intent.getBooleanExtra("safe_mode",false)
    @UsedByGodot fun resumeGame(): Boolean=host.intent.getBooleanExtra("resume",true)
    @UsedByGodot fun processMemoryMb(): Long=android.os.Debug.getPss().toLong()/1024
}
