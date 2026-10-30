package id.npc.aoe2launcher

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class ModPackagesTest {
    private val sample=File("../samples/ModernEraExpansion")
    private fun pack(extra: Pair<String,ByteArray>?=null, change: (String,ByteArray)->ByteArray={_,b -> b}): ByteArray {
        val out=ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            sample.walkTopDown().filter { it.isFile }.forEach { f ->
                val n=f.relativeTo(sample).invariantSeparatorsPath
                zip.putNextEntry(ZipEntry(n)); zip.write(change(n,f.readBytes())); zip.closeEntry()
            }
            if(extra!=null) { zip.putNextEntry(ZipEntry(extra.first)); zip.write(extra.second); zip.closeEntry() }
        }; return out.toByteArray()
    }
    private fun withMods(test: (File)->Unit) { val dir=Files.createTempDirectory("mods-test").toFile(); try { test(dir) } finally { dir.deleteRecursively() } }
    private fun rejected(block: ()->Unit) { try { block(); fail("Expected validation rejection") } catch(_: IllegalArgumentException) {} }
    @Test fun installsSampleWithoutChangingOriginalFiles()=withMods { mods ->
        val base=File(mods,"original.txt").apply { writeText("original") }
        assertEquals("npc.modern-era",ModPackages.install(pack().inputStream(),mods))
        ModPackages.validateOrder(mods,listOf("npc.modern-era"))
        assertEquals("original",base.readText()); assertFalse(File(mods,".installing").exists())
    }
    @Test fun rejectsTraversalAndAmbiguousNames()=withMods { mods ->
        for(path in listOf("../escape","/absolute","sprites/../escape.png","sprites\\escape.png","sprites//escape.png")) {
            rejected { ModPackages.install(pack(path to byteArrayOf(1)).inputStream(),mods) }
            assertFalse(File(mods,".installing").exists())
        }
    }
    @Test fun rejectsExecutablePackages()=withMods { mods ->
        for(path in listOf("scripts/mod.gd","assets/mod.pck","lib/hook.so","classes.dex")) rejected { ModPackages.install(pack(path to byteArrayOf(1)).inputStream(),mods) }
    }
    @Test fun enforcesActualExtractedBytes()=withMods { mods ->
        rejected { ModPackages.install(pack("sprites/bomb.png" to ByteArray(8_000_001)).inputStream(),mods) }
    }
    @Test fun incompatibleFrameworkIsRejected()=withMods { mods ->
        val data=pack { name,b -> if(name=="manifest.json") JSONObject(String(b)).put("frameworkVersion","99.0.0").toString().toByteArray() else b }
        rejected { ModPackages.install(data.inputStream(),mods) }
    }
    @Test fun dependencyMustExistAtExactVersionEarlier()=withMods { mods ->
        val data=pack { name,b -> if(name=="manifest.json") JSONObject(String(b)).put("dependencies",JSONArray().put(JSONObject().put("id","npc.foundation").put("version","1.0.0"))).toString().toByteArray() else b }
        ModPackages.install(data.inputStream(),mods)
        rejected { ModPackages.validateOrder(mods,listOf("npc.modern-era")) }
    }
    @Test fun conflictingIdsAreRejected()=withMods { mods ->
        ModPackages.install(pack().inputStream(),mods)
        val data=pack { name,b -> if(name=="manifest.json") JSONObject(String(b)).put("id","npc.conflict").toString().toByteArray() else b }
        ModPackages.install(data.inputStream(),mods)
        rejected { ModPackages.validateOrder(mods,listOf("npc.modern-era","npc.conflict")) }
    }
    @Test fun disabledModsDoNotLoad()=withMods { mods -> ModPackages.validateOrder(mods,emptyList()) }
    @Test fun invalidPngCannotInstall()=withMods { mods ->
        val data=pack { name,b -> if(name.endsWith(".png")) ByteArray(24) else b }
        rejected { ModPackages.install(data.inputStream(),mods) }
    }
}
