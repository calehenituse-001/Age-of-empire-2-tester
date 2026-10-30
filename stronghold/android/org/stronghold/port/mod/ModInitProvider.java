package org.stronghold.port.mod;

import android.app.Activity;
import android.app.Application;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.util.Log;
import android.view.View;
import java.util.WeakHashMap;
import org.stronghold.port.StrongholdModOverlay;

/**
 * Bootstrap for the original Extreme activity, in the :extreme process only.
 *
 * Android constructs providers before Activity.onCreate. Defer the overlay
 * attachment until the decor view is attached and the Activity is resumed,
 * so it is not lost during the game's initial SurfaceView setup.
 */
public final class ModInitProvider extends ContentProvider implements Application.ActivityLifecycleCallbacks {
    private static final String TAG = "StrongholdModBoot";
    private static final String EXTREME = "org.stronghold.port.ExtremeGameActivity";

    private final Handler main = new Handler(Looper.getMainLooper());
    private final WeakHashMap<Activity,StrongholdModOverlay> overlays = new WeakHashMap<>();
    private final WeakHashMap<Activity,Boolean> resumed = new WeakHashMap<>();

    @Override public boolean onCreate() {
        Context context = getContext();
        if (context == null || !(context.getApplicationContext() instanceof Application)) {
            Log.e(TAG, "Provider failed to obtain Application; Mod Menu cannot attach");
            return false;
        }
        ((Application)context.getApplicationContext()).registerActivityLifecycleCallbacks(this);
        Log.i(TAG, "Provider initialized; pid=" + Process.myPid() + ", waiting for Extreme activity");
        return true;
    }

    @Override public void onActivityResumed(Activity activity) {
        if (!EXTREME.equals(activity.getClass().getName())) return;
        resumed.put(activity, Boolean.TRUE);
        Log.i(TAG, "Extreme resumed; scheduling overlay installation");
        View decor = activity.getWindow().getDecorView();
        // View.post runs after attachment. main.post is a fallback if the decor
        // is already attached and the game's first layout has not completed.
        Runnable install = () -> {
            if (!Boolean.TRUE.equals(resumed.get(activity)) || activity.isFinishing() || activity.isDestroyed()) return;
            try {
                StrongholdModOverlay overlay = overlays.get(activity);
                if (overlay == null) {
                    overlay = new StrongholdModOverlay(activity);
                    overlays.put(activity, overlay);
                    Log.i(TAG, "MOD bubble attached to " + activity.getClass().getName());
                }
                overlay.resume();
                Log.i(TAG, "MOD bubble resumed");
            } catch (RuntimeException | LinkageError error) {
                Log.e(TAG, "Failed to create or display MOD bubble", error);
            }
        };
        if (decor.isAttachedToWindow()) main.post(install);
        else decor.post(install);
    }

    @Override public void onActivityPaused(Activity activity) {
        resumed.remove(activity);
        StrongholdModOverlay overlay = overlays.get(activity);
        if (overlay != null) overlay.pause();
    }

    @Override public void onActivityDestroyed(Activity activity) {
        resumed.remove(activity);
        StrongholdModOverlay overlay = overlays.remove(activity);
        if (overlay != null) overlay.detach();
    }

    @Override public void onActivityCreated(Activity activity, android.os.Bundle state) {}
    @Override public void onActivityStarted(Activity activity) {}
    @Override public void onActivityStopped(Activity activity) {}
    @Override public void onActivitySaveInstanceState(Activity activity, android.os.Bundle state) {}

    @Override public Cursor query(Uri u, String[] p, String s, String[] a, String o) { return null; }
    @Override public String getType(Uri u) { return null; }
    @Override public Uri insert(Uri u, ContentValues v) { return null; }
    @Override public int delete(Uri u, String s, String[] a) { return 0; }
    @Override public int update(Uri u, ContentValues v, String s, String[] a) { return 0; }
}
