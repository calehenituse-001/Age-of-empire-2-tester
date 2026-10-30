package id.npc.aoe2launcher

import android.app.Activity
import android.app.ActivityManager
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.widget.*
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

class LauncherActivity: Activity() {
    private lateinit var storage: Storage
    private lateinit var column: LinearLayout
    private val worker=Executors.newSingleThreadExecutor()
    private var busy=false
    private fun dp(n: Int)=(n*resources.displayMetrics.density).toInt()
    override fun onCreate(state: Bundle?) { super.onCreate(state); storage=Storage(this); home() }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    private fun page(title: String,subtitle: String) {
        val scroll=ScrollView(this).apply { setBackgroundColor(Color.rgb(14,25,22)); isFillViewport=true }
        column=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; setPadding(dp(28),dp(20),dp(28),dp(24)) }
        scroll.addView(column); setContentView(scroll); label(title,28); label(subtitle,16)
    }
    private fun label(text: String,size: Int=18): TextView=TextView(this).also {
        it.text=text; it.textSize=size.toFloat(); it.setTextColor(if(size>20) Color.rgb(219,184,109) else Color.WHITE); it.setPadding(0,dp(8),0,dp(10)); column.addView(it)
    }
    private fun button(text: String,action: ()->Unit) {
        val b=Button(this).apply {
            this.text=text; textSize=18f; isAllCaps=false; minHeight=dp(54); setTextColor(Color.WHITE)
            background=GradientDrawable().apply { setColor(Color.rgb(34,51,42)); cornerRadius=dp(8).toFloat(); setStroke(dp(1),Color.rgb(74,92,67)) }
            setOnClickListener { if(!busy) action() }
        }; column.addView(b,LinearLayout.LayoutParams(-1,-2).apply { bottomMargin=dp(9) })
    }
    private fun toggle(text: String,on: Boolean,changed: (Boolean)->Unit) {
        val s=Switch(this).apply {
            this.text="$text   ${if(on) "ON" else "OFF"}"; textSize=18f; minHeight=dp(56); setTextColor(Color.WHITE); isChecked=on
            setOnCheckedChangeListener { _,enabled -> this.text="$text   ${if(enabled) "ON" else "OFF"}"; changed(enabled) }
        }; column.addView(s)
    }
    private fun choose(title: String,values: List<String>,selected: (Int)->Unit) {
        AlertDialog.Builder(this).setTitle(title).setItems(values.toTypedArray()) { d,i -> selected(i); d.dismiss() }.setNegativeButton("Cancel",null).show()
    }
    private fun error(e: Throwable) { runCatching { storage.log(e.stackTraceToString()) }; AlertDialog.Builder(this).setTitle("Action could not finish").setMessage(e.message).setPositiveButton("OK",null).show() }
    private fun job(title: String,finished: ((String)->Unit)?=null,action: ((String)->Unit)->String) {
        busy=true; val dialog=AlertDialog.Builder(this).setTitle(title).setMessage("Preparing…").setCancelable(false).create(); dialog.show()
        worker.execute {
            val result=runCatching { action { message -> runOnUiThread { if(!isDestroyed) dialog.setMessage(message) } } }
            runOnUiThread { busy=false; if(!isDestroyed) {
                dialog.dismiss(); home()
                result.onSuccess { if(finished!=null) finished(it) else AlertDialog.Builder(this).setTitle("Complete").setMessage(it).setPositiveButton("OK",null).show() }.onFailure(::error)
            } }
        }
    }
    private fun configSet(k: String,v: Any) { val c=storage.read("Config/launcher.json"); c.put(k,v); storage.write("Config/launcher.json",c) }
    private fun activeMods()=ModPackages.strings(storage.read("Config/mods.json").optJSONArray("enabled"))
    private fun home() {
        page("AGE OF EMPIRES II","Custom Launcher · 0.1.0 · Offline single-player\n${if(storage.file("GameData/raw/.revision").exists()) "Game files imported" else "Import your own AoE2 HD (2013) files to begin"}")
        button("PLAY GAME") { launch(false,true) }; button("GAME SETTINGS",::settings); button("PERFORMANCE SETTINGS",::performance)
        button("CHEAT MOD MENU",::cheats); button("GAMEPLAY MOD MANAGER",::mods); button("GAME FILE MANAGER",::files); button("ABOUT",::about)
        button("SAFE MODE · resume vanilla save") { launch(true,true) }
    }
    private fun launch(safe: Boolean,resume: Boolean) {
        if(!storage.file("GameData/raw/.revision").isFile) { files(); return }
        val am=getSystemService(ACTIVITY_SERVICE) as ActivityManager
        if(am.deviceConfigurationInfo.reqGlEsVersion<0x30000) { error(IllegalStateException("OpenGL ES 3.0 is required by this engine.")); return }
        job("Verify launch",finished={ startActivity(Intent(this,GameActivity::class.java).putExtra("safe_mode",safe).putExtra("resume",resume)) }) { progress ->
            progress("Checking game files and mod dependencies")
            require(GameFiles.REQUIRED.all { storage.file("GameData/raw/$it").length()>0 }) { "Missing/empty game files; reimport the HD folder." }
            if(!safe) ModPackages.validateOrder(storage.file("Mods"),activeMods())
            if(!resume) storage.backupSaves()
            "Game started"
        }
    }
    private fun settings() {
        val c=storage.read("Config/launcher.json"); page("Game settings","Applies to new games. Civilization, sound and touch controls remain available in the original in-game settings.")
        for((key,values) in mapOf("difficulty" to listOf("easy","medium","hard"),"opponent" to listOf("rival","raids")))
            button("$key: ${c.optString(key,if(key=="difficulty") "medium" else "rival")}") { choose(key,values) { configSet(key,values[it]); settings() } }
        button("Map size: ${c.optInt("mapSize",128)}") { choose("Map size",listOf("96","128","160")) { configSet("mapSize",listOf(96,128,160)[it]); settings() } }
        button("START NEW GAME · automatic save backup") { launch(false,false) }; button("BACK",::home)
    }
    private fun performance() {
        val c=storage.read("Config/launcher.json"); page("Performance","GLES compatibility renderer · ${c.optString("preset","BALANCED")}\nAI frequency and game simulation speed are unchanged.")
        for((name,note) in listOf("LOW" to "70% · 30 FPS · reduced cosmetic effects","BALANCED" to "85% · 60 FPS","HIGH" to "100% · 60 FPS"))
            button("$name — $note") { configSet("preset",name); configSet("resolutionPercent",when(name) { "LOW"->70; "HIGH"->100; else->85 }); performance() }
        val title=label("Internal resolution: ${c.optInt("resolutionPercent",85)}%")
        val seek=SeekBar(this).apply { max=50; progress=c.optInt("resolutionPercent",85).coerceIn(50,100)-50 }
        seek.setOnSeekBarChangeListener(object: SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(s: SeekBar?,p: Int,user: Boolean) { title.text="Internal resolution: ${p+50}%" }
            override fun onStartTrackingTouch(s: SeekBar?) {}
            override fun onStopTrackingTouch(s: SeekBar) { configSet("resolutionPercent",s.progress+50) }
        }); column.addView(seek)
        toggle("FPS and memory diagnostics",c.optBoolean("diagnostics",false)) { configSet("diagnostics",it) }
        button("BACK",::home)
    }
    private fun cheats() {
        page("Cheat mod menu","Human player only · defaults OFF · offline only\nChanges here apply on next launch; use the floating CHEATS button while playing.")
        val c=storage.read("Cheats/config.json")
        val flags=linkedMapOf("food" to "Unlimited Food","wood" to "Unlimited Wood","gold" to "Unlimited Gold","stone" to "Unlimited Stone","resource_multiplier" to "Resource Income Multiplier","instant_build" to "Instant Construction","build_multiplier" to "Construction Multiplier","free_build" to "Ignore Construction Costs","instant_train" to "Instant Training","train_multiplier" to "Training Multiplier","instant_upgrade" to "Instant Unit Upgrades","instant_research" to "Instant Research","research_multiplier" to "Research Multiplier","free_research" to "Ignore Research Costs","population_override" to "Population Override")
        flags.forEach { (key,name) -> toggle(name,c.optBoolean(key,false)) { c.put(key,it); storage.write("Cheats/config.json",c) } }
        for(key in listOf("resource","build","train","research")) button("$key multiplier: ×${c.optInt("${key}_factor",2)}") {
            val nums=listOf(2,5,10,25,50,100); choose("$key multiplier",nums.map { "×$it" }) { c.put("${key}_factor",nums[it]); storage.write("Cheats/config.json",c); cheats() }
        }
        button("Population override: ${c.optInt("population_limit",500)}") { choose("Population",listOf("200","500","1000")) { c.put("population_limit",listOf(200,500,1000)[it]); storage.write("Cheats/config.json",c); cheats() } }
        label("Unlimited bypasses spending and retains the real balance. OFF restores normal rules; completed work and earned resources remain. Combat multipliers are future extension points.",16)
        button("DISABLE ALL CHEATS") { storage.write("Cheats/config.json",JSONObject()); cheats() }; button("BACK",::home)
    }
    private fun changeMods(order: List<String>) {
        job("Validate mods and back up saves") {
            ModPackages.validateOrder(storage.file("Mods"),order); storage.backupSaves(); storage.write("Config/mods.json",JSONObject().put("enabled",JSONArray(order)))
            "Selection saved. Modded games use a separate save profile."
        }
    }
    private fun mods() {
        page("Gameplay mods","Format v1 · new buildings supported\nMods load at startup. Dependencies must precede dependents.")
        button("INSTALL MOD ZIP") { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { type="*/*"; addCategory(Intent.CATEGORY_OPENABLE) },2) }
        button("INSTALL MODERN ERA SAMPLE") { job("Install sample") { ModPackages.install(assets.open("modern-era-sample.zip"),storage.file("Mods")); "Installed and disabled. Enable it in the Mod Manager." } }
        val order=activeMods()
        for((dir,m) in ModPackages.installed(storage.file("Mods"))) {
            val id=dir.name; val i=order.indexOf(id); label("${m.optString("name",id)} ${m.optString("version")} · ${if(i<0) "OFF" else "ON #${i+1}"}",22)
            button(if(i<0) "ENABLE $id" else "DISABLE $id") { changeMods(if(i<0) order+id else order-id) }
            if(i>0) button("MOVE UP") { val n=order.toMutableList(); java.util.Collections.swap(n,i,i-1); changeMods(n) }
            if(i>=0 && i<order.lastIndex) button("MOVE DOWN") { val n=order.toMutableList(); java.util.Collections.swap(n,i,i+1); changeMods(n) }
            if(i<0) button("DELETE $id") { AlertDialog.Builder(this).setMessage("Delete $id? Saves are kept.").setPositiveButton("Delete") { _,_ -> dir.deleteRecursively(); mods() }.setNegativeButton("Cancel",null).show() }
        }; button("BACK",::home)
    }
    private fun files() {
        page("Game file manager","Select HD (2013), with Data and Bin in the selected folder. Definitive Edition and PC save files are unsupported.")
        button("IMPORT GAME FOLDER") { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION),1) }
        button("VERIFY IMPORTED FILES") {
            val missing=GameFiles.REQUIRED.filter { storage.file("GameData/raw/$it").length()<=0 }
            AlertDialog.Builder(this).setMessage(if(missing.isEmpty()) "Required files present. First launch validates and converts game data." else "Missing:\n${missing.joinToString("\n")}").setPositiveButton("OK",null).show()
        }
        button("EXPORT SAVES AND LOGS ZIP") { startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply { type="application/zip"; addCategory(Intent.CATEGORY_OPENABLE); putExtra(Intent.EXTRA_TITLE,"AoE2-saves-logs.zip") },3) }
        label("App-private storage keeps data separate from the APK. Keep the source folder and export saves before uninstalling. The reference APK has separate private saves.",16); button("BACK",::home)
    }
    private fun about() {
        val am=getSystemService(ACTIVITY_SERVICE) as ActivityManager
        page("About","0.1.0 · Godot 4.7.2 · GLES ${am.deviceConfigurationInfo.glEsVersion}\n${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL} · ${android.os.Build.SUPPORTED_ABIS.joinToString()}")
        label("Unofficial GPL-3.0-or-later project based on the supplied Domotix.co source. Godot is MIT. Age of Empires II belongs to its respective owners. No original game data is bundled.\n\nSource: github.com/calehenituse-001/Age-of-empire-2-tester\n\nFull gameplay and Mali performance require testing with your own HD data.",16); button("BACK",::home)
    }
    @Deprecated("Framework picker without extra UI dependencies")
    override fun onActivityResult(request: Int,result: Int,data: Intent?) {
        super.onActivityResult(request,result,data); if(result!=RESULT_OK) return; val uri=data?.data ?: return
        when(request) {
            1 -> job("Import game files") { progress ->
                runCatching { contentResolver.takePersistableUriPermission(uri,Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                storage.backupSaves(); GameFiles(contentResolver,storage).import(uri,progress); "Copied. PLAY GAME converts the source data."
            }
            2 -> job("Install mod") { contentResolver.openInputStream(uri).use { ModPackages.install(requireNotNull(it),storage.file("Mods")) }; "Installed; disabled by default." }
            3 -> job("Export saves/logs") {
                contentResolver.openOutputStream(uri,"w").use { output ->
                    java.util.zip.ZipOutputStream(requireNotNull(output).buffered()).use { zip ->
                        for(folder in listOf("Saves","Logs")) storage.file(folder).walkTopDown().filter { it.isFile }.forEach { f ->
                            zip.putNextEntry(java.util.zip.ZipEntry(f.relativeTo(storage.root).invariantSeparatorsPath)); f.inputStream().use { it.copyTo(zip) }; zip.closeEntry()
                        }
                    }
                }; "Saves and logs exported."
            }
        }
    }
    @Deprecated("Native Activity navigation") override fun onBackPressed() { if(!busy) home() }
}
