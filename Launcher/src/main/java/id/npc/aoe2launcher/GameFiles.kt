package id.npc.aoe2launcher
import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract as DC
import java.io.File

class GameFiles(private val resolver: ContentResolver,private val storage: Storage) {
    companion object {
        val REQUIRED=listOf("Data/empires2_x1_p1.dat","Data/graphics.drs","Data/interfac.drs","Data/terrain.drs","Data/sounds.drs","Data/sounds_x1.drs","Data/blendomatic_x1.dat","Data/pal_2.pal","Data/pal_4.pal","Data/Slp/foak_nn.slp","Data/Slp/fpin_nn.slp","Bin/en/language.dll")
        val OPTIONAL=listOf("Bin/en/language_x1.dll","Bin/en/language_x1_p1.dll","Sound/music/music1.mp3","Sound/music/xmusic1.mp3")
    }
    private fun child(tree: Uri,parent: String,name: String): String? {
        resolver.query(DC.buildChildDocumentsUriUsingTree(tree,parent),arrayOf(DC.Document.COLUMN_DOCUMENT_ID,DC.Document.COLUMN_DISPLAY_NAME),null,null,null)?.use { c ->
            while(c.moveToNext()) if(c.getString(1).equals(name,true)) return c.getString(0)
        }; return null
    }
    private fun resolve(tree: Uri,path: String): Uri? {
        var id=DC.getTreeDocumentId(tree)
        for(part in path.split('/')) id=child(tree,id,part) ?: return null
        return DC.buildDocumentUriUsingTree(tree,id)
    }
    fun import(tree: Uri,progress: (String)->Unit) {
        val sources=(REQUIRED+OPTIONAL).associateWith { resolve(tree,it) }
        val missing=REQUIRED.filter { sources[it]==null }
        require(missing.isEmpty()) { "Select the HD (2013) folder containing Data and Bin. Missing:\n${missing.joinToString("\n")}" }
        val stage=storage.file("GameData/raw.staging"); stage.deleteRecursively(); check(stage.mkdirs())
        var bytes=0L
        try {
            for((path,uri) in sources) {
                if(uri==null) continue
                progress("Copying $path"); val target=File(stage,path); target.parentFile!!.mkdirs()
                resolver.openInputStream(uri).use { input ->
                    requireNotNull(input) { "Cannot read $path" }
                    target.outputStream().buffered().use { out ->
                        val buffer=ByteArray(65536)
                        while(true) { val n=input.read(buffer); if(n<0) break; bytes+=n; require(bytes<=1500000000L) { "Input exceeds 1.5 GB" }; out.write(buffer,0,n) }
                    }
                }; require(target.length()>0) { "$path is empty" }
            }
            File(stage,".revision").writeText(System.currentTimeMillis().toString())
            val raw=storage.file("GameData/raw"); val previous=storage.file("GameData/raw.previous"); previous.deleteRecursively()
            if(raw.exists()) check(raw.renameTo(previous)) { "Cannot preserve previous data" }
            if(!stage.renameTo(raw)) { previous.renameTo(raw); error("Cannot commit import") }
            previous.deleteRecursively(); storage.log("Imported $bytes bytes via SAF")
        } catch(e: Exception) { stage.deleteRecursively(); throw e }
    }
}
