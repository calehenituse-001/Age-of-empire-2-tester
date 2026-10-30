#pragma once
#include <stdint.h>
#define MOD_SITE_COUNT 9
#define MOD_UNLIMITED_MASK ((1u<<2)|(1u<<4)|(1u<<6)|(1u<<7)|(1u<<15)|(255u<<17))
typedef struct {
    uint32_t unlimited_mask, spawn_milli, instant_spawn, reserved;
    uint32_t seen[9], applied[9], denied[9], owner[9], reason[9];
    uint32_t mode, local, viewer, participant, ai_type;
    uint32_t item_applied[25];
    uint32_t spawn_remainder[9];
} ModControl;
static inline uint32_t read_control(const uint32_t *p) { return __atomic_load_n(p, __ATOMIC_RELAXED); }
static inline void write_control(uint32_t *p, uint32_t v) { __atomic_store_n(p, v, __ATOMIC_RELAXED); }
