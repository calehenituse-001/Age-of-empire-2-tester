package org.stronghold.port;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Rect;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.InputType;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;
import android.util.Log;

/** A single small decor child when closed. No full-screen invisible touch interceptor. */
public final class StrongholdModOverlay {
    private final Activity activity;
    private final FrameLayout decor;
    private final WindowManager windowManager;
    private final WindowManager.LayoutParams bubbleParams;
    private final boolean attachedAsPanel;
    private final Button bubble;
    private final SharedPreferences prefs;
    private final StrongholdNativeBridge bridge=new StrongholdNativeBridge();
    private final View.OnLayoutChangeListener layoutListener;
    private AlertDialog dialog;
    private float normX,normY,downX,downY,startX,startY;
    private boolean dragging;
    private final int slop;
    private static final int BG=0xff172027, FG=0xfff4f0df, MUTED=0xffbac5c9, GOLD=0xffefc66b;

    public StrongholdModOverlay(Activity a) {
        activity=a;decor=(FrameLayout)a.getWindow().getDecorView();
        windowManager=(WindowManager)a.getSystemService(Context.WINDOW_SERVICE);
        if(windowManager==null || decor.getWindowToken()==null)
            throw new IllegalStateException("Extreme window is not attached to WindowManager");
        prefs=a.getSharedPreferences("stronghold_mod_v33",Context.MODE_PRIVATE);
        normX=readPosition("button_x",0.35f);normY=readPosition("button_y",0.34f);
        slop=ViewConfiguration.get(a).getScaledTouchSlop();
        bubble=new Button(a);bubble.setText("MOD");bubble.setTextSize(17);bubble.setTextColor(0xff171717);
        bubble.setAllCaps(false);bubble.setPadding(0,0,0,0);bubble.setMinWidth(0);bubble.setMinHeight(0);
        bubble.setBackground(background(0xfff4ce55,12));bubble.setElevation(dp(100));
        bubble.setContentDescription("Buka Stronghold Mod Menu. Geser untuk memindahkan.");
        // Native game surfaces can be composited above normal Activity children.
        // An application-attached panel stays above the game's SurfaceView
        // without requesting the dangerous system-overlay permission.
        bubbleParams=new WindowManager.LayoutParams(
            dp(64),dp(48),WindowManager.LayoutParams.TYPE_APPLICATION_PANEL,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
              | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
              | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT);
        bubbleParams.token=decor.getWindowToken();
        bubbleParams.gravity=Gravity.TOP|Gravity.LEFT;
        boolean panel = false;
        try {
            windowManager.addView(bubble,bubbleParams);
            panel = true;
            Log.i("StrongholdModBoot", "MOD button attached as application panel");
        } catch (RuntimeException e) {
            Log.e("StrongholdModBoot", "Panel failed; trying Activity decor fallback", e);
            decor.addView(bubble,new FrameLayout.LayoutParams(dp(64),dp(48),Gravity.TOP|Gravity.LEFT));
        }
        attachedAsPanel=panel;
        bubble.setOnClickListener(v->open());
        bubble.setOnTouchListener((v,event)->touch(event));
        layoutListener=(v,l,t,r,b,ol,ot,or,ob)->position();
        decor.addOnLayoutChangeListener(layoutListener);
    }
    private float readPosition(String key,float fallback) {
        try {float f=prefs.getFloat(key,fallback);return Float.isNaN(f)?fallback:Math.max(0,Math.min(1,f));}
        catch(ClassCastException bad){return fallback;}
    }
    public void resume() {
        bubble.setVisibility(View.VISIBLE);
        bridge.apply(ModSettings.load(prefs));
        bubble.post(()->{if(bubble.getParent()!=null)position();});
    }
    public void pause() {if(dialog!=null)dialog.dismiss();bubble.setVisibility(View.GONE);}
    public void detach() {
        pause();
        decor.removeOnLayoutChangeListener(layoutListener);
        if(bubble.getParent()!=null) {
            if(attachedAsPanel)windowManager.removeViewImmediate(bubble);
            else decor.removeView(bubble);
        }
    }
    private int dp(int value){return (int)(value*activity.getResources().getDisplayMetrics().density+0.5f);}
    private GradientDrawable background(int color,int radius) {
        GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;
    }
    private Rect bounds() {
        Rect visible=new Rect();decor.getWindowVisibleDisplayFrame(visible);
        int left=Math.max(dp(4),visible.left+dp(4));
        int top=Math.max(dp(4),visible.top+dp(4));
        int right=visible.right-dp(68);
        int bottom=visible.bottom-dp(52);
        return new Rect(left,top,Math.max(left,right),Math.max(top,bottom));
    }
    private void position() {
        Rect b=bounds();int x=b.left+Math.round(normX*b.width());
        int y=b.top+Math.round(normY*b.height());
        if(attachedAsPanel) {
            bubbleParams.x=x;bubbleParams.y=y;
            if(bubble.getParent()!=null)windowManager.updateViewLayout(bubble,bubbleParams);
        } else {bubble.setX(x);bubble.setY(y);bubble.bringToFront();}
    }
    private boolean touch(MotionEvent e) {
        switch(e.getActionMasked()) {
        case MotionEvent.ACTION_DOWN:
            dragging=false;downX=e.getRawX();downY=e.getRawY();startX=attachedAsPanel?bubbleParams.x:bubble.getX();startY=attachedAsPanel?bubbleParams.y:bubble.getY();return true;
        case MotionEvent.ACTION_MOVE:
            float dx=e.getRawX()-downX,dy=e.getRawY()-downY;
            if(dx*dx+dy*dy>slop*slop)dragging=true;
            if(dragging){
                Rect b=bounds();
                int x=Math.round(Math.max(b.left,Math.min(b.right,startX+dx)));
                int y=Math.round(Math.max(b.top,Math.min(b.bottom,startY+dy)));
                if(attachedAsPanel){bubbleParams.x=x;bubbleParams.y=y;windowManager.updateViewLayout(bubble,bubbleParams);}
                else {bubble.setX(x);bubble.setY(y);bubble.bringToFront();}
            }
            return true;
        case MotionEvent.ACTION_UP:
            if(dragging){Rect b=bounds();float x=attachedAsPanel?bubbleParams.x:bubble.getX();
                float y=attachedAsPanel?bubbleParams.y:bubble.getY();
                normX=b.width()>0?(x-b.left)/b.width():0;
                normY=b.height()>0?(y-b.top)/b.height():0;prefs.edit().putFloat("button_x",normX).putFloat("button_y",normY).apply();}
            else bubble.performClick();return true;
        case MotionEvent.ACTION_CANCEL:position();return true;
        default:return true;
        }
    }
    private TextView text(String s,int size,int color) {
        TextView t=new TextView(activity);t.setText(s);t.setTextSize(size);t.setTextColor(color);t.setPadding(dp(8),dp(7),dp(8),dp(7));return t;
    }
    private Button button(String label) {Button b=new Button(activity);b.setText(label);b.setAllCaps(false);b.setTextSize(16);return b;}
    private LinearLayout column(){LinearLayout l=new LinearLayout(activity);l.setOrientation(LinearLayout.VERTICAL);return l;}
    private LinearLayout category(LinearLayout root,String title,boolean expanded) {
        Button heading=button((expanded?"▾ ":"▸ ")+title);heading.setTextColor(GOLD);heading.setGravity(Gravity.LEFT|Gravity.CENTER_VERTICAL);
        heading.setBackground(background(0xff27343d,4));root.addView(heading,new LinearLayout.LayoutParams(-1,dp(48)));
        LinearLayout content=column();content.setPadding(dp(6),dp(4),dp(6),dp(12));content.setVisibility(expanded?View.VISIBLE:View.GONE);root.addView(content);
        heading.setOnClickListener(v->{boolean show=content.getVisibility()!=View.VISIBLE;content.setVisibility(show?View.VISIBLE:View.GONE);heading.setText((show?"▾ ":"▸ ")+title);});return content;
    }
    private void unlimited(LinearLayout root,ModSettings draft,int id,String name,boolean available) {
        LinearLayout row=new LinearLayout(activity);row.setGravity(Gravity.CENTER_VERTICAL);
        Switch s=new Switch(activity);s.setText("Unlimited "+name+"  ");s.setTextSize(18);s.setTextColor(FG);s.setTextOn("ON");s.setTextOff("OFF");s.setShowText(true);
        s.setMinHeight(dp(52));s.setChecked(draft.enabled(id));s.setEnabled(available);
        s.setOnCheckedChangeListener((v,on)->draft.set(id,on));row.addView(s,new LinearLayout.LayoutParams(0,-2,1));
        Button reset=button("Reset");reset.setEnabled(available);reset.setOnClickListener(v->s.setChecked(false));row.addView(reset,new LinearLayout.LayoutParams(dp(88),-2));root.addView(row);
    }
    private void toast(String s){Toast.makeText(activity,s,Toast.LENGTH_LONG).show();}
    private void open() {
        if(activity.isFinishing() || activity.isDestroyed() || (dialog!=null && dialog.isShowing()))return;
        final boolean installed=bridge.available();final ModSettings draft=ModSettings.load(prefs);
        LinearLayout panel=column();panel.setPadding(dp(12),dp(8),dp(12),dp(8));panel.setBackgroundColor(BG);
        TextView title=text("STRONGHOLD • MOD 3.3",21,GOLD);title.setTypeface(null,Typeface.BOLD);panel.addView(title);
        TextView status=text(installed?"Hook terpasang • Gameplay Android belum diuji":"Hook tidak tersedia • Fitur dinonaktifkan",16,installed?0xffa9e3b2:0xffffaf91);panel.addView(status);
        panel.addView(text("Offline Extreme skirmish/trail. ON adalah permintaan; filter sesi dan pemain tetap diperiksa pada setiap event. Tekan Apply untuk menyimpan.",14,MUTED));
        ScrollView scroll=new ScrollView(activity);scroll.setFillViewport(false);LinearLayout content=column();scroll.addView(content);panel.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout gold=category(content,"Gold",true);unlimited(gold,draft,15,"Gold",installed);
        gold.addView(text("Hook biaya rekrut biasa/Arab, pembelian dan debit Gold. Pendapatan tetap normal. Saldo awal harus cukup; cakupan pengeluaran perlu diuji di perangkat.",15,MUTED));
        LinearLayout materials=category(content,"Bahan bangunan",false);
        int[] materialIds={2,4,6,7};String[] materialNames={"Wood","Stone","Iron","Pitch"};
        for(int i=0;i<materialIds.length;i++)unlimited(materials,draft,materialIds[i],materialNames[i],installed);
        materials.addView(text("Hanya jalur biaya konstruksi yang dipetakan. Tidak mencakup bahan baku industri, stok nol, atau multiplier produksi.",15,MUTED));
        LinearLayout weapons=category(content,"Senjata & armor",false);
        String[] equipment={"Bow","Crossbow","Spear","Pike","Mace","Sword","Leather Armor","Metal Armor"};
        for(int i=0;i<8;i++)unlimited(weapons,draft,i+17,equipment[i],installed);
        weapons.addView(text("No-consumption pada rekrut reguler dengan stok yang cukup. Pengaturan Gold tetap terpisah.",15,MUTED));
        LinearLayout worker=category(content,"Peasant spawn",false);
        worker.addView(text("Multiplier 1–100 (desimal sampai 3 digit)",18,FG));
        EditText multiplier=new EditText(activity);multiplier.setTextColor(FG);multiplier.setTextSize(20);multiplier.setSingleLine(true);multiplier.setInputType(InputType.TYPE_CLASS_NUMBER|InputType.TYPE_NUMBER_FLAG_DECIMAL);multiplier.setText(draft.multiplierText());multiplier.setEnabled(installed);multiplier.setSelectAllOnFocus(true);worker.addView(multiplier);
        Button resetRate=button("Reset multiplier ×1");resetRate.setEnabled(installed);resetRate.setOnClickListener(v->multiplier.setText("1"));worker.addView(resetRate);
        Switch instant=new Switch(activity);instant.setText("Instant Peasant Spawn  ");instant.setTextColor(FG);instant.setTextSize(18);instant.setTextOn("ON");instant.setTextOff("OFF");instant.setShowText(true);instant.setChecked(draft.instantSpawn);instant.setEnabled(installed);instant.setMinHeight(dp(52));worker.addView(instant);
        Button resetInstant=button("Reset Instant OFF");resetInstant.setEnabled(installed);resetInstant.setOnClickListener(v->instant.setChecked(false));worker.addView(resetInstant);
        worker.addView(text("Instant memprioritaskan interval minimum saat kondisi spawn asli terpenuhi. Multiplier tetap disimpan terpisah. Housing, popularitas, idle peasants dan batas unit tetap berlaku.",15,MUTED));
        LinearLayout unavailable=category(content,"Belum tersedia",false);
        unavailable.addView(text("Production ×1–100: belum dipasang.\nWheat, Flour, Bread, Cheese, Meat, Apples, Hops, Beer: Unlimited belum dipasang.\nUnlimited stok nol: belum didukung.\nRecruitment Speed / Instant Recruitment: tidak ada timer tervalidasi.\nConstruction Speed / Instant Construction: tidak ada timer tervalidasi.\nCrusader HD / Stronghold Classic: belum dipatch.",16,MUTED));
        LinearLayout debug=category(content,"Debug / Diagnostics",false);
        TextView diagnostics=text(bridge.diagnostics(),14,FG);diagnostics.setTypeface(Typeface.MONOSPACE);diagnostics.setTextIsSelectable(true);debug.addView(diagnostics);
        Button refresh=button("Refresh diagnostics");refresh.setOnClickListener(v->diagnostics.setText(bridge.diagnostics()));debug.addView(refresh);
        Button copy=button("Copy diagnostics");copy.setOnClickListener(v->{ClipboardManager c=(ClipboardManager)activity.getSystemService(Context.CLIPBOARD_SERVICE);c.setPrimaryClip(ClipData.newPlainText("Stronghold diagnostics",bridge.diagnostics()));toast("Diagnostics disalin.");});debug.addView(copy);
        LinearLayout actions=new LinearLayout(activity);actions.setGravity(Gravity.CENTER_VERTICAL);
        Button apply=button("Apply & Save"), resetAll=button("Reset All"), close=button("Tutup");
        actions.addView(apply,new LinearLayout.LayoutParams(0,dp(52),1));actions.addView(resetAll,new LinearLayout.LayoutParams(0,dp(52),1));actions.addView(close,new LinearLayout.LayoutParams(0,dp(52),1));panel.addView(actions);
        dialog=new AlertDialog.Builder(activity,android.R.style.Theme_Material_Dialog_NoActionBar).setView(panel).create();
        dialog.setOnDismissListener(d->{if(dialog==d)dialog=null;});
        apply.setEnabled(installed);apply.setOnClickListener(v->{
            try {draft.spawnMilli=ModSettings.parseMultiplier(multiplier.getText().toString());}
            catch(IllegalArgumentException bad){multiplier.setError(bad.getMessage());worker.setVisibility(View.VISIBLE);multiplier.requestFocus();return;}
            draft.instantSpawn=instant.isChecked();
            if(bridge.apply(draft)){draft.save(prefs);status.setText("Tersimpan • ON diminta; periksa applied di Diagnostics");diagnostics.setText(bridge.diagnostics());toast("Pengaturan diterapkan dan disimpan.");}
            else {status.setText("Hook tidak tersedia; pengaturan tidak diterapkan.");toast("Hook tidak tersedia.");}
        });
        resetAll.setOnClickListener(v->{ModSettings defaults=new ModSettings();bridge.apply(defaults);defaults.save(prefs);dialog.dismiss();open();});
        close.setOnClickListener(v->dialog.dismiss());dialog.show();
        Window w=dialog.getWindow();if(w!=null){w.setBackgroundDrawable(background(BG,12));w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);w.setLayout(Math.min(dp(740),decor.getWidth()-dp(24)),Math.max(dp(220),decor.getHeight()-dp(24)));}
    }
}
