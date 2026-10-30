/* Version-locked ARM64 event hooks for the user's original Extreme library.
 * No scans, JNI, allocation, game-loop polling, or modifications to unit limits.
 * Native register frame belongs to hooks.S; guest x86 pointers are NOT native pointers.
 */
#include <stdint.h>
#include "mod_shared.h"
extern ModControl mod_control;
extern const unsigned char image_base[];
__attribute__((used)) const char hook_signature[] = "SHMOD033";
#define GUEST_BASE UINT64_C(0x2000000000)
#define STRIDE 0x39f4u
#define STOCK_BASE 0x0122c330u
#define GOLD_BASE (STOCK_BASE + 15*4)
static uint32_t rd(uint32_t a) { return *(volatile uint32_t *)(GUEST_BASE | a); }

/* Reasons: 0 applied, 1 disabled, 2 mode, 3 slot, 4 participant,
 * 5 duplicate participant, 6 AI, 7 other owner, 8 insufficient stock,
 * 9 source not allowed, 10 invalid amount/flag, 11 income, 12 pointer mismatch.
 * Mode 99 + game mode 3 is deliberately the only supported session.
 */
static unsigned owner_gate(unsigned owner) {
    ModControl *c=&mod_control;
    unsigned mode=rd(0x248ca00), local=rd(0x25f8748);
    write_control(&c->mode,mode); write_control(&c->local,local);
    write_control(&c->viewer,rd(0x25f874c));
    write_control(&c->participant,0); write_control(&c->ai_type,0xffffffffu);
    if(mode!=99 || rd(0x2bb8ee8)!=3) return 2;
    if(local<1 || local>8 || owner<1 || owner>8) return 3;
    unsigned pid=rd(0x248ca90+local*4), ai=rd(0x248cafc+local*4);
    write_control(&c->participant,pid); write_control(&c->ai_type,ai);
    if(pid!=1) return 4; // Offline setup explicitly passes participant ID 1 to resolver.
    unsigned matches=0;
    for(unsigned slot=1;slot<=8;slot++) if(rd(0x248ca90+slot*4)==1) matches++;
    if(matches!=1) return 5;
    if(ai!=0) return 6;
    return owner==local ? 0 : 7;
}
static void record(unsigned site,unsigned owner,unsigned reason) {
    ModControl *c=&mod_control;
    write_control(&c->seen[site],read_control(&c->seen[site])+1);
    write_control(&c->owner[site],owner);write_control(&c->reason[site],reason);
    if(reason==0)write_control(&c->applied[site],read_control(&c->applied[site])+1);
    else if(reason!=1)write_control(&c->denied[site],read_control(&c->denied[site])+1);
}
static unsigned ptr_owner(uint64_t p,uint32_t base) {
    if((p & UINT64_C(0xffffffff00000000))!=GUEST_BASE) return 0;
    uint32_t a=(uint32_t)p;
    if(a<base || (a-base)%STRIDE) return 0;
    unsigned owner=(a-base)/STRIDE;
    return owner<=8 ? owner : 0;
}
static void gold(uint64_t *r,unsigned site,unsigned pointer_reg,unsigned value_reg) {
    unsigned owner=ptr_owner(r[pointer_reg],GOLD_BASE), reason=1;
    if(read_control(&mod_control.unlimited_mask)&(1u<<15)) {
        reason=owner_gate(owner);
        if(!reason) {
            int32_t old=(int32_t)rd((uint32_t)r[pointer_reg]), next=(int32_t)r[value_reg];
            if(old<0)reason=8;
            else if(next>=old)reason=11;
            else r[value_reg]=(uint32_t)old;
        }
    }
    record(site,owner,reason);
}
static unsigned equipment_source(uint64_t lr) {
    return lr==0x2520b70 || lr==0x2520c44 || lr==0x2520d20;
}
static unsigned building_source(uint64_t lr) {
    switch(lr) {
    case 0x2c5ae80:case 0x2c5b000:case 0x2c5b12c:case 0x2c5b1e8:
    case 0x2c5b2ac:case 0x2c5b374:case 0x2c5b68c:case 0x2c5b740:
    case 0x2c5b7fc:case 0x2c5b8d8:return 1;
    default:return 0;
    }
}
static void inventory(uint64_t *r) {
    unsigned item=(uint32_t)r[8], esp=(uint32_t)r[16], owner=0,reason=1;
    if(item<25 && (read_control(&mod_control.unlimited_mask)&(1u<<item))) {
        owner=rd(esp+4);reason=owner_gate(owner);
        if(!reason) {
            int32_t qty=(int32_t)rd(esp+12);
            uint64_t caller=r[30]-(uintptr_t)image_base;
            if(rd(esp+8)!=item || rd(esp+16)!=0 || qty<=0)reason=10;
            else if(item!=15 && !((item>=17 && item<=24 && equipment_source(caller)) ||
                     ((item==2 || item==4 || item==6 || item==7) && building_source(caller))))reason=9;
            else if((int32_t)rd(STOCK_BASE+owner*STRIDE+item*4)<qty)reason=8;
            else {
                // Existing id=0 early-return cleans the original virtual stack.
                // Skip BOTH aggregate and physical-stock removal, never refund later.
                r[8]=0;
                write_control(&mod_control.item_applied[item],read_control(&mod_control.item_applied[item])+1);
            }
        }
    }
    record(7,owner,reason);
}
static void peasant(uint64_t *r) {
    unsigned owner=(uint32_t)r[11], reason=1;
    unsigned milli=read_control(&mod_control.spawn_milli), instant=read_control(&mod_control.instant_spawn);
    if(instant || milli>1000) {
        reason=owner_gate(owner);
        if(!reason) {
            uint32_t ptr=0x122bed0+owner*STRIDE;
            int32_t rate=(int32_t)r[15];
            if((uint32_t)r[9]!=ptr || r[17]!=(GUEST_BASE|ptr))reason=12;
            else if(rate<=0)reason=10;
            else {
                if(milli<1000 || milli>100000)milli=1000;
                uint64_t n=(uint64_t)(uint32_t)rate*milli+read_control(&mod_control.spawn_remainder[owner]);
                write_control(&mod_control.spawn_remainder[owner],(uint32_t)(n%1000));
                n/=1000;
                if(instant || n>4000)n=4000;
                r[15]=(uint32_t)n;
            }
        }
    }
    if(reason && owner<=8)write_control(&mod_control.spawn_remainder[owner],0);
    record(8,owner,reason);
}
void mod_dispatch(uint64_t *registers,unsigned site) {
    switch(site) {
    case 0:gold(registers,site,15,17);break;
    case 1:gold(registers,site,16,17);break;
    case 2:gold(registers,site,14,15);break;
    case 3:gold(registers,site,16,17);break;
    case 4:gold(registers,site,14,13);break;
    case 5:gold(registers,site,10,9);break;
    case 6:gold(registers,site,16,17);break;
    case 7:inventory(registers);break;
    case 8:peasant(registers);break;
    }
}
