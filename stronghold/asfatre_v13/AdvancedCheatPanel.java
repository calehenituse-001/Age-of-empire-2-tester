package org.stronghold.port;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

/**
 * Accessible replacement panel for Asfatre v1.3's EXISTING Cheat control.
 *
 * This class is a drop-in integration component, not a standalone overlay.
 * Integration in the proprietary v1.3 GameActivity still requires a verified
 * DEX edit that calls show(activity, cheatSender) from its existing Cheat path.
 * The caller MUST forward X/Q through the game's original queueCheat logic.
 * Any player-only mod controls require a version-verified native bridge.
 */
public final class AdvancedCheatPanel {
    public interface CheatSender { void send(char key); }

    private static final int BG=0xff172027, FG=0xfff7f0df, GOLD=0xffefc66b;
    private static final int MUTE=0xffbbc9d0;
    private final Activity activity;
    private final CheatSender cheatSender;
    private final StrongholdNativeBridge bridge;
    private final SharedPreferences preferences;
    private AlertDialog dialog;

    private AdvancedCheatPanel(Activity activity, CheatSender sender) {
        this.activity=activity;this.cheatSender=sender;
        this.bridge=new StrongholdNativeBridge();
        this.preferences=activity.getSharedPreferences("stronghold_asfatre_mod",Context.MODE_PRIVATE);
    }

    public static void show(Activity activity, CheatSender sender) {
        if(activity==null || sender==null || activity.isFinishing() || activity.isDestroyed())return;
        if(android.os.Looper.myLooper()!=android.os.Looper.getMainLooper()) {
            activity.runOnUiThread(()->show(activity,sender));
            return;
        }
        new AdvancedCheatPanel(activity,sender).open();
    }

    /**
     * Designed for the original CheatMenu click callback. This avoids adding a
     * method reference to private GameActivity.queueCheat in the external DEX.
     * Reflection here targets the app's OWN private method, not a system API.
     */
    public static void openForView(View clicked) {
        Context ctx=clicked.getContext();
        while(ctx instanceof android.content.ContextWrapper && !(ctx instanceof Activity)) {
            Context parent=((android.content.ContextWrapper)ctx).getBaseContext();
            if(parent==null || parent==ctx)break;
            ctx=parent;
        }
        if(!(ctx instanceof Activity))return;
        final Activity a=(Activity)ctx;
        show(a,key->{
            try {
                java.lang.reflect.Method target=null;
                for(Class<?> cls=a.getClass();cls!=null;cls=cls.getSuperclass()) {
                    try {target=cls.getDeclaredMethod("queueCheat",char.class);break;}
                    catch(NoSuchMethodException missing) { /* search the base Activity */ }
                }
                if(target==null)throw new NoSuchMethodException("GameActivity.queueCheat(char)");
                target.setAccessible(true);
                target.invoke(a,key);
            } catch(ReflectiveOperationException | SecurityException failure) {
                android.util.Log.e("AsfatreModMenu","Original cheat command could not be sent",failure);
                Toast.makeText(a,"Perintah cheat gagal: lihat log",Toast.LENGTH_LONG).show();
            }
        });
    }

    private int dp(int v){return (int)(v*activity.getResources().getDisplayMetrics().density+0.5f);}
    private TextView text(String s,int size,int color){
        TextView t=new TextView(activity);t.setText(s);t.setTextSize(size);
        t.setTextColor(color);t.setPadding(dp(10),dp(8),dp(10),dp(8));return t;
    }
    private LinearLayout column(){
        LinearLayout l=new LinearLayout(activity);l.setOrientation(LinearLayout.VERTICAL);return l;
    }
    private Button button(String s){
        Button b=new Button(activity);b.setText(s);b.setAllCaps(false);
        b.setTextSize(17);b.setMinHeight(dp(49));return b;
    }
    private void toast(String s){Toast.makeText(activity,s,Toast.LENGTH_SHORT).show();}
    private GradientDrawable bg(){
        GradientDrawable d=new GradientDrawable();d.setColor(BG);
        d.setCornerRadius(dp(10));return d;
    }

    private LinearLayout category(LinearLayout parent,String heading,boolean expanded){
        LinearLayout body=column();
        body.setVisibility(expanded?View.VISIBLE:View.GONE);
        Button head=button((expanded?"▾ ":"▸ ")+heading);
        head.setTextColor(GOLD);
        parent.addView(head,new LinearLayout.LayoutParams(-1,dp(50)));
        parent.addView(body);
        head.setOnClickListener(v->{
            boolean open=body.getVisibility()!=View.VISIBLE;
            body.setVisibility(open?View.VISIBLE:View.GONE);
            head.setText((open?"▾ ":"▸ ")+heading);
        });
        return body;
    }

    private void quick(LinearLayout parent,String label,char key,String description) {
        Button b=button(label);parent.addView(b,new LinearLayout.LayoutParams(-1,dp(54)));
        parent.addView(text(description,13,MUTE));
        b.setOnClickListener(v->{
            // This is Asfatre's existing cheat-input route, never a new simulation.
            cheatSender.send(key);
            toast("Perintah Alt+"+key+" dikirim ke engine");
        });
    }

    private void item(LinearLayout parent,ModSettings draft,String name,int id,boolean ready){
        LinearLayout row=new LinearLayout(activity);row.setGravity(Gravity.CENTER_VERTICAL);
        Switch control=new Switch(activity);control.setText(name);
        control.setTextSize(17);control.setTextColor(FG);control.setShowText(true);
        control.setTextOn("ON");control.setTextOff("OFF");
        control.setChecked(draft.enabled(id));control.setEnabled(ready);
        control.setOnCheckedChangeListener((view,on)->draft.set(id,on));
        row.addView(control,new LinearLayout.LayoutParams(0,dp(56),1));
        parent.addView(row);
    }
    private void open() {
        if(activity.isFinishing() || activity.isDestroyed())return;
        final boolean available=bridge.available();
        // Never pass a v3.3 bridge against unmodified Asfatre v1.3 as if working.
        final ModSettings draft=ModSettings.load(preferences);

        LinearLayout root=column();
        root.setBackground(bg());root.setPadding(dp(12),dp(12),dp(12),dp(6));
        TextView title=text("STRONGHOLD • CHEAT & MOD",21,GOLD);
        title.setTypeface(null,Typeface.BOLD);root.addView(title);
        root.addView(text("Cheat cepat memakai sistem Asfatre v1.3. Mod tambahan hanya aktif bila library native yang cocok terpasang.",14,MUTE));

        ScrollView scroll=new ScrollView(activity);
        LinearLayout content=column();scroll.addView(content);
        root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));

        LinearLayout quick=category(content,"Cheat bawaan Asfatre",true);
        quick(quick,"Tambah Gold + Popularity (Alt+X)",'X',
                "Perintah game asli. Perubahan jumlah Gold tergantung engine.");
        quick(quick,"Perintah Alt+Q",'Q',
                "Fungsi Alt+Q belum divalidasi pada v1.3. Uji sebelum dipakai di save penting.");

        LinearLayout gold=category(content,"Gold & bahan bangunan",false);
        item(gold,draft,"Unlimited Gold",15,available);
        int[] resources={2,4,6,7};
        String[] resNames={"Unlimited Wood","Unlimited Stone","Unlimited Iron","Unlimited Pitch"};
        for(int i=0;i<resources.length;i++)item(gold,draft,resNames[i],resources[i],available);

        LinearLayout military=category(content,"Senjata & Armor",false);
        String[] weapons={"Bow","Crossbow","Spear","Pike","Mace","Sword","Leather Armor","Metal Armor"};
        for(int i=0;i<weapons.length;i++)item(military,draft,"Unlimited "+weapons[i],17+i,available);

        LinearLayout workers=category(content,"Peasant",false);
        workers.addView(text("Multiplier Peasant Spawn ×1–100",17,FG));
        EditText number=new EditText(activity);
        number.setSingleLine(true);number.setTextColor(FG);number.setTextSize(20);
        number.setInputType(InputType.TYPE_CLASS_NUMBER|InputType.TYPE_NUMBER_FLAG_DECIMAL);
        number.setText(draft.multiplierText());number.setEnabled(available);
        workers.addView(number);
        Switch instant=new Switch(activity);instant.setText("Instant Peasant");
        instant.setTextColor(FG);instant.setTextSize(17);instant.setShowText(true);
        instant.setTextOn("ON");instant.setTextOff("OFF");
        instant.setChecked(draft.instantSpawn);instant.setEnabled(available);
        workers.addView(instant);

        LinearLayout info=category(content,"Status & diagnostik",false);
        info.addView(text(available
                ?"JNI terhubung. Periksa diagnostik: hook dan filter pemain tetap perlu diuji dalam game."
                :"Native mod belum terhubung pada build ini. Tombol Unlimited dan Peasant sengaja dikunci.",14,MUTE));
        TextView diagnostic=text(bridge.diagnostics(),13,FG);
        diagnostic.setTextIsSelectable(true);info.addView(diagnostic);
        Button refresh=button("Perbarui diagnostik");
        refresh.setOnClickListener(v->diagnostic.setText(bridge.diagnostics()));
        info.addView(refresh);

        content.addView(text("Belum didukung: Unlimited Food, multiplier produksi, bypass stok nol, Instant Recruitment/Construction. Batas pasukan dan AI tidak boleh diubah.",13,MUTE));

        LinearLayout actions=new LinearLayout(activity);
        Button apply=button("Terapkan"),reset=button("Reset"),close=button("Tutup");
        apply.setEnabled(available);reset.setEnabled(available);
        actions.addView(apply,new LinearLayout.LayoutParams(0,dp(50),1));
        actions.addView(reset,new LinearLayout.LayoutParams(0,dp(50),1));
        actions.addView(close,new LinearLayout.LayoutParams(0,dp(50),1));
        root.addView(actions);

        dialog=new AlertDialog.Builder(activity).setView(root).create();
        apply.setOnClickListener(v->{
            try {draft.spawnMilli=ModSettings.parseMultiplier(number.getText().toString());}
            catch(IllegalArgumentException error){number.setError(error.getMessage());return;}
            draft.instantSpawn=instant.isChecked();
            if(bridge.apply(draft)){
                draft.save(preferences);toast("Pengaturan dikirim. Periksa diagnostik untuk hasil hook.");
                diagnostic.setText(bridge.diagnostics());
            } else toast("Mod native belum terhubung.");
        });
        reset.setOnClickListener(v->{
            ModSettings d=new ModSettings();
            if(bridge.apply(d)){d.save(preferences);dialog.dismiss();open();}
            else toast("Mod native belum terhubung.");
        });
        close.setOnClickListener(v->dialog.dismiss());
        dialog.show();
        Window window=dialog.getWindow();
        if(window!=null){
            window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
            int width=Math.min(dp(750),Math.max(dp(280),activity.getResources().getDisplayMetrics().widthPixels-dp(24)));
            int height=Math.max(dp(250),activity.getResources().getDisplayMetrics().heightPixels-dp(24));
            window.setLayout(width,height);
        }
    }
}
