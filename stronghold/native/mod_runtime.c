#define _GNU_SOURCE
#include <jni.h>
#include <link.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "mod_shared.h"
#include "generated.h"
static int locate(struct dl_phdr_info *info,size_t size,void *data) {
    (void)size;
    const char *name=strrchr(info->dlpi_name,'/');name=name?name+1:info->dlpi_name;
    if(strcmp(name,"libstronghold.so"))return 0;
    int code=0,control=0;
    for(unsigned i=0;i<info->dlpi_phnum;i++) {
        const ElfW(Phdr) *p=&info->dlpi_phdr[i];
        if(p->p_type!=PT_LOAD)continue;
        if((p->p_flags&PF_R) && SIGNATURE_VA>=p->p_vaddr && SIGNATURE_VA+9<=p->p_vaddr+p->p_memsz)code=1;
        if((p->p_flags&PF_W) && CONTROL_VA>=p->p_vaddr && CONTROL_VA+sizeof(ModControl)<=p->p_vaddr+p->p_memsz)control=1;
    }
    if(code && control && !memcmp((void *)(info->dlpi_addr+SIGNATURE_VA),"SHMOD033",9))
        *(ModControl **)data=(ModControl *)(info->dlpi_addr+CONTROL_VA);
    return 1;
}
static ModControl *state(void) { ModControl *s=NULL;dl_iterate_phdr(locate,&s);return s; }
JNIEXPORT jboolean JNICALL Java_org_stronghold_port_StrongholdNativeBridge_nativeAvailable(JNIEnv *env,jclass cls) {
    (void)env;(void)cls;return state()!=NULL;
}
JNIEXPORT jboolean JNICALL Java_org_stronghold_port_StrongholdNativeBridge_nativeApply(JNIEnv *env,jclass cls,jint mask,jint milli,jboolean instant) {
    (void)env;(void)cls;
    ModControl *c=state();
    if(!c || ((uint32_t)mask&~MOD_UNLIMITED_MASK) || milli<1000 || milli>100000)return JNI_FALSE;
    write_control(&c->unlimited_mask,(uint32_t)mask);
    write_control(&c->spawn_milli,(uint32_t)milli);write_control(&c->instant_spawn,instant?1:0);
    return JNI_TRUE;
}
JNIEXPORT jstring JNICALL Java_org_stronghold_port_StrongholdNativeBridge_nativeDiagnostics(JNIEnv *env,jclass cls) {
    (void)cls;ModControl *c=state();
    if(!c)return (*env)->NewStringUTF(env,"Hook tidak tersedia. Memerlukan Extreme 0.3.1-DEV dengan patch v3.3 yang cocok.");
    char out[3400];
    int n=snprintf(out,sizeof(out),"v3.3: hook ARM64 terpasang.\nGameplay Android: BELUM diuji.\n"
        "Mask permintaan: 0x%08x; peasant x%.3f; instant %u\n"
        "Sesi pada event terakhir: mode=%u, local=%u, viewer=%u, ID=%u, AI type=%u\n\n",
        read_control(&c->unlimited_mask),read_control(&c->spawn_milli)/1000.0,read_control(&c->instant_spawn),
        read_control(&c->mode),read_control(&c->local),read_control(&c->viewer),read_control(&c->participant),read_control(&c->ai_type));
    const char *names[]={"Regular recruit","Arab recruit","Market","Trade","Siege","Gold transfer","Ally gold","Inventory debit","Peasant timer"};
    for(unsigned i=0;i<9 && n<(int)sizeof(out)-180;i++)
        n+=snprintf(out+n,sizeof(out)-(size_t)n,"%s: seen=%u applied=%u denied=%u owner=%u reason=%u\n",names[i],
            read_control(&c->seen[i]),read_control(&c->applied[i]),read_control(&c->denied[i]),read_control(&c->owner[i]),read_control(&c->reason[i]));
    snprintf(out+n,sizeof(out)-(size_t)n,"\nReason: 0 applied; 1 OFF; 2 sesi tidak didukung; 3 slot invalid; 4 ID; 5 ID duplikat; 6 AI; 7 owner lain; 8 stok; 9 sumber; 10 jumlah/flag; 11 income; 12 pointer.\n"
        "Counters adalah observasi hook, bukan bukti AI isolation atau keberhasilan gameplay. Hanya offline skirmish/trail (mode 99 + game 3). Stok awal nol belum didukung.");
    return (*env)->NewStringUTF(env,out);
}
