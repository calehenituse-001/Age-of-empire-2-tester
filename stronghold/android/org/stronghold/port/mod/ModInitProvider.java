package org.stronghold.port.mod;

import android.app.Activity;
import android.app.Application;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import java.util.WeakHashMap;
import org.stronghold.port.StrongholdModOverlay;

/** Bootstrap in :extreme only; preserves the launcher's original DEX and Application. */
public final class ModInitProvider extends ContentProvider implements Application.ActivityLifecycleCallbacks {
    private final WeakHashMap<Activity,StrongholdModOverlay> overlays=new WeakHashMap<>();
    @Override public boolean onCreate() {
        if(getContext()==null)return false;
        ((Application)getContext().getApplicationContext()).registerActivityLifecycleCallbacks(this);
        return true;
    }
    @Override public void onActivityResumed(Activity a) {
        if(!"org.stronghold.port.ExtremeGameActivity".equals(a.getClass().getName()))return;
        StrongholdModOverlay overlay=overlays.get(a);
        if(overlay==null){overlay=new StrongholdModOverlay(a);overlays.put(a,overlay);}
        overlay.resume();
    }
    @Override public void onActivityPaused(Activity a) {StrongholdModOverlay o=overlays.get(a);if(o!=null)o.pause();}
    @Override public void onActivityDestroyed(Activity a) {StrongholdModOverlay o=overlays.remove(a);if(o!=null)o.detach();}
    @Override public void onActivityCreated(Activity a,Bundle b){}
    @Override public void onActivityStarted(Activity a){}
    @Override public void onActivityStopped(Activity a){}
    @Override public void onActivitySaveInstanceState(Activity a,Bundle b){}
    @Override public Cursor query(Uri u,String[] p,String s,String[] a,String o){return null;}
    @Override public String getType(Uri u){return null;}
    @Override public Uri insert(Uri u,ContentValues v){return null;}
    @Override public int delete(Uri u,String s,String[] a){return 0;}
    @Override public int update(Uri u,ContentValues v,String s,String[] a){return 0;}
}
