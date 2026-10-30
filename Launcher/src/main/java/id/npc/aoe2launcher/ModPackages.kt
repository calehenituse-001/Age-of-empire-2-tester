package id.npc.aoe2launcher

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.io.DataInputStream
import java.util.zip.ZipInputStream

/** Versioned declarative additions. No mod code executes inside the app. */
object ModPackages {
    const val GAME="aoe2hd-beta-source-1"
    const val FRAMEWORK="1.0.0"
    private val ids=Regex("[a-z][a-z0-9_.-]{2,63}")
    private val versions=Regex("[0-9]{1,4}\\.[0-9]{1,4}\\.[0-9]{1,4}")
    fun strings(a: JSONArray?): List<String> = if(a==null) emptyList() else (0 until a.length()).map { a.getString(it) }
    fun safePath(n: String): Boolean = n.isNotEmpty() && n.length<=200 && !n.startsWith('/') && !n.contains('\\') && !n.contains(':') && n.split('/').all { it.isNotEmpty() && it!="." && it!=".." && it.none { c -> c.code<32 } }
    fun validateManifest(m: JSONObject) {
        require(m.getInt("formatVersion")==1) { "Unsupported mod format" }
        require(ids.matches(m.getString("id")) && versions.matches(m.getString("version"))) { "Invalid ID/version" }
        for(k in listOf("name","author")) require(m.getString(k).length in 1..100)
        require(m.getString("gameVersion")==GAME) { "Incompatible game version" }
        require(m.getString("frameworkVersion")==FRAMEWORK) { "Incompatible framework version" }
        require(strings(m.getJSONArray("capabilities"))==listOf("buildings.add")) { "Only buildings.add is supported in v1" }
        val seen=hashSetOf<String>(); val dependencies=m.getJSONArray("dependencies")
        for(i in 0 until dependencies.length()) {
            val d=dependencies.getJSONObject(i); val id=d.getString("id")
            require(ids.matches(id) && id!=m.getString("id") && seen.add(id) && versions.matches(d.getString("version"))) { "Invalid dependency" }
        }
    }
    fun content(dir: File)=JSONObject(File(dir,"content.json").readText())
    fun validateContent(dir: File): Set<Int> {
        val c=content(dir); require(c.keys().asSequence().toSet()==setOf("buildings")) { "Unsupported registry" }
        val b=c.getJSONArray("buildings"); require(b.length() in 1..32)
        val used=hashSetOf<Int>(); val keys=hashSetOf<String>()
        for(i in 0 until b.length()) {
            val row=b.getJSONObject(i)
            require(row.getInt("id") in 900000..999999 && used.add(row.getInt("id"))) { "Invalid/duplicate content ID" }
            require(ids.matches(row.getString("key")) && keys.add(row.getString("key"))) { "Invalid/duplicate building key" }
            require(row.getString("name").length in 1..80)
            require(row.getInt("baseId") in listOf(70,562,584,68)) { "Unsupported building adapter" }
            require(row.getInt("size") in 1..4 && row.getInt("hp") in 1..100000 && row.getInt("population") in 0..50 && row.getInt("requiredAge") in 0..3 && row.getDouble("seconds") in 1.0..3600.0)
            val cost=row.getJSONObject("cost")
            require(cost.keys().asSequence().all { it in listOf("food","wood","gold","stone") && cost.getInt(it) in 0..100000 })
            require(strings(row.getJSONArray("dropoff")).all { it in listOf("food","wood","gold","stone") })
            val path=row.getString("sprite")
            require(safePath(path) && path.startsWith("sprites/") && path.endsWith(".png")) { "Invalid sprite path" }
            val file=File(dir,path); require(file.isFile && file.length() in 24..8000000) { "Missing/oversized sprite" }
            val header=ByteArray(24).also { h -> DataInputStream(file.inputStream()).use { it.readFully(h) } }
            require(header.take(8).toByteArray().contentEquals(byteArrayOf(-119,80,78,71,13,10,26,10))) { "Invalid PNG" }
            fun int32(at: Int)=(0..3).fold(0) { v,off -> (v shl 8) or (header[at+off].toInt() and 255) }
            val w=int32(16); val h=int32(20)
            require(w in 1..2048 && h in 1..2048 && row.getInt("hotspotX") in 0..w && row.getInt("hotspotY") in 0..h) { "Invalid dimensions/hotspot" }
        }; return used
    }
    fun install(input: InputStream,mods: File): String {
        mods.mkdirs(); val temp=File(mods,".installing"); temp.deleteRecursively(); check(temp.mkdirs())
        try {
            ZipInputStream(input.buffered()).use { zip ->
                val names=hashSetOf<String>(); var total=0L; var count=0
                while(true) {
                    val e=zip.nextEntry ?: break; val name=e.name.removeSuffix("/")
                    require(safePath(name) && names.add(name.lowercase()) && ++count<=256) { "Unsafe, duplicate or excessive ZIP paths" }
                    if(e.isDirectory) { zip.closeEntry(); continue }
                    require(name in listOf("manifest.json","content.json","README.md") || (name.startsWith("sprites/") && name.endsWith(".png"))) { "Unsupported package file $name" }
                    val file=File(temp,name); file.parentFile!!.mkdirs(); var size=0L
                    file.outputStream().use { out ->
                        val buffer=ByteArray(32768)
                        while(true) { val n=zip.read(buffer); if(n<0) break; total+=n; size+=n; require(total<=64000000 && size<=8000000) { "ZIP extraction limit exceeded" }; out.write(buffer,0,n) }
                    }; zip.closeEntry()
                }
            }
            require(File(temp,"manifest.json").length()<=32768 && File(temp,"content.json").length()<=262144) { "Metadata too large" }
            val m=JSONObject(File(temp,"manifest.json").readText()); validateManifest(m); validateContent(temp)
            val id=m.getString("id"); val dest=File(mods,id)
            require(!dest.exists()) { "Already installed. Disable/delete the existing version before replacing it." }
            check(temp.renameTo(dest)); return id
        } finally { temp.deleteRecursively() }
    }
    fun installed(mods: File): List<Pair<File,JSONObject>> = mods.listFiles()?.filter { it.isDirectory && !it.name.startsWith('.') }?.mapNotNull { d -> runCatching { d to JSONObject(File(d,"manifest.json").readText()) }.getOrNull() }?.sortedBy { it.first.name } ?: emptyList()
    fun validateOrder(mods: File,order: List<String>) {
        require(order.distinct().size==order.size && order.size<=32)
        val loaded=hashMapOf<String,String>(); val used=hashSetOf<Int>(); val keys=hashSetOf<String>()
        for(id in order) {
            require(ids.matches(id)); val dir=File(mods,id); val m=JSONObject(File(dir,"manifest.json").readText()); validateManifest(m)
            require(m.getString("id")==id)
            val deps=m.getJSONArray("dependencies")
            for(i in 0 until deps.length()) { val d=deps.getJSONObject(i); require(loaded[d.getString("id")]==d.getString("version")) { "$id needs ${d.getString("id")} ${d.getString("version")} earlier in load order" } }
            for(n in validateContent(dir)) require(used.add(n)) { "Content ID conflict: $n" }
            val bs=content(dir).getJSONArray("buildings")
            for(i in 0 until bs.length()) require(keys.add(bs.getJSONObject(i).getString("key"))) { "Building key conflict" }
            loaded[id]=m.getString("version")
        }
    }
}
