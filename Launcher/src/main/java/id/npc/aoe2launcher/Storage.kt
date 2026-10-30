package id.npc.aoe2launcher
import android.app.Application
import android.content.Context
import android.util.AtomicFile
import org.json.JSONObject
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class Storage(context: Context) {
    val root = File(context.filesDir,"AgeOfEmpires2").apply { mkdirs() }
    init { listOf("Launcher","GameData","Mods","Cheats","Config","Saves","Logs").forEach { file(it).mkdirs() } }
    fun file(path: String) = File(root,path)
    fun read(path: String): JSONObject = try {
        if(file(path).exists()) JSONObject(String(AtomicFile(file(path)).readFully(),Charsets.UTF_8)) else JSONObject()
    } catch(e: Exception) {
        runCatching { log("Invalid configuration $path: ${e.message}"); file(path).copyTo(file("Logs/${System.currentTimeMillis()}-${File(path).name}.invalid"),true) }
        JSONObject()
    }
    fun write(path: String,data: JSONObject) {
        file(path).parentFile!!.mkdirs(); val atomic=AtomicFile(file(path)); val out=atomic.startWrite()
        try { out.write(data.toString(2).toByteArray()); atomic.finishWrite(out) } catch(e: Exception) { atomic.failWrite(out); throw e }
    }
    fun log(text: String) {
        val f=file("Logs/launcher.log"); if(f.length()>1000000) f.renameTo(file("Logs/launcher.previous.log"))
        f.appendText("${java.time.Instant.now()} $text\n")
    }
    fun backupSaves(): File {
        val out=file("Saves/backups/${System.currentTimeMillis()}.zip"); out.parentFile!!.mkdirs()
        ZipOutputStream(out.outputStream().buffered()).use { zip ->
            file("Saves").walkTopDown().onEnter { it.name!="backups" }.filter { it.isFile }.forEach { f ->
                zip.putNextEntry(ZipEntry(f.relativeTo(file("Saves")).invariantSeparatorsPath)); f.inputStream().use { it.copyTo(zip) }; zip.closeEntry()
            }
        }; return out
    }
}
class LauncherApplication: Application() {
    override fun onCreate() {
        super.onCreate(); val previous=Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t,e ->
            runCatching { Storage(this).file("Logs/crash-${System.currentTimeMillis()}.txt").writeText(e.stackTraceToString()) }
            previous?.uncaughtException(t,e)
        }
    }
}
