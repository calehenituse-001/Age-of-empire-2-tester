package org.stronghold.port;

/** UI calls only: no JNI polling during gameplay. */
public final class StrongholdNativeBridge {
    private boolean loaded;
    public StrongholdNativeBridge() {
        try {System.loadLibrary("stronghold_mod_runtime");loaded=true;}
        catch(UnsatisfiedLinkError | SecurityException unavailable){loaded=false;}
    }
    private static native boolean nativeAvailable();
    private static native boolean nativeApply(int mask,int milli,boolean instant);
    private static native String nativeDiagnostics();
    public boolean available() {return loaded && nativeAvailable();}
    public boolean apply(ModSettings s) {return available() && nativeApply(s.unlimitedMask,s.spawnMilli,s.instantSpawn);}
    public String diagnostics() {return loaded?nativeDiagnostics():"JNI bridge tidak dapat dimuat. Semua fitur nonaktif.";}
}
