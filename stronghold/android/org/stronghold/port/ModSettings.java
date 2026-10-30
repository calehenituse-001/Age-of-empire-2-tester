package org.stronghold.port;

import android.content.SharedPreferences;
import java.math.BigDecimal;

/** Only implemented settings are loaded. Unsupported keys never reach native code. */
public final class ModSettings {
    public static final int ALLOWED_MASK=(1<<2)|(1<<4)|(1<<6)|(1<<7)|(1<<15)|(255<<17);
    public int unlimitedMask=0;
    public int spawnMilli=1000;
    public boolean instantSpawn=false;
    public static int parseMultiplier(String text) {
        String s=text.trim().replace(',', '.');
        if(!s.matches("[0-9]{1,3}(\\.[0-9]{1,3})?"))throw new IllegalArgumentException("Masukkan 1–100, maksimal 3 angka desimal.");
        BigDecimal value=new BigDecimal(s);
        if(value.compareTo(BigDecimal.ONE)<0 || value.compareTo(new BigDecimal("100"))>0)
            throw new IllegalArgumentException("Multiplier harus 1–100.");
        return value.multiply(new BigDecimal("1000")).intValueExact();
    }
    public String multiplierText() {return BigDecimal.valueOf(spawnMilli,3).stripTrailingZeros().toPlainString();}
    public boolean enabled(int id) {return (unlimitedMask&(1<<id))!=0;}
    public void set(int id,boolean on) {if(on)unlimitedMask|=1<<id;else unlimitedMask&=~(1<<id);unlimitedMask&=ALLOWED_MASK;}
    public static ModSettings load(SharedPreferences prefs) {
        ModSettings s=new ModSettings();
        try {
            s.unlimitedMask=prefs.getInt("unlimited_mask",0)&ALLOWED_MASK;
            int n=prefs.getInt("spawn_milli",1000);s.spawnMilli=n>=1000 && n<=100000 ? n:1000;
            s.instantSpawn=prefs.getBoolean("instant_spawn",false);
        } catch(ClassCastException invalid){return new ModSettings();}
        return s;
    }
    public void save(SharedPreferences prefs) {
        prefs.edit().putInt("schema",33).putInt("unlimited_mask",unlimitedMask&ALLOWED_MASK)
            .putInt("spawn_milli",spawnMilli).putBoolean("instant_spawn",instantSpawn).apply();
    }
}
