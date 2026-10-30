package id.npc.aoe2launcher
import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class StartupTest {
    @Test fun nativeLauncherAndRealGodotBootWithoutAssets() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val log=Storage(context).file("Logs/godot.log"); log.delete()
        ActivityScenario.launch(LauncherActivity::class.java).use { activity ->
            activity.onActivity { a ->
                assertNotNull(a.window.decorView)
                a.startActivity(Intent(a,GameActivity::class.java).putExtra("safe_mode",true))
            }
            val deadline=System.currentTimeMillis()+60_000
            var output=""
            while(System.currentTimeMillis()<deadline) {
                output=if(log.exists()) log.readText() else ""
                if(output.contains("BOOT_READY_MISSING_DATA")) break
                Thread.sleep(250)
            }
            assertTrue("Godot must reach its real missing-data screen: $output",output.contains("BOOT_READY_MISSING_DATA"))
            assertFalse("No script runtime errors: $output",output.contains("SCRIPT ERROR"))
        }
    }
}
