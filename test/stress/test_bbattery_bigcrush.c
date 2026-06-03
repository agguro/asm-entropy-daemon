#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

/* TestU01 Headers */
#include "unif01.h"
#include "bbattery.h"

#define SHM_PATH "/dev/shm/chaos_shm"
#define NUM_SLOTS 64

typedef struct {
    uint64_t vlag;
    uint64_t data;
    uint8_t  padding[48]; // Padding naar 64 bytes voor cache-line alignment
} slot_t;

slot_t *shm_base;

/* 
 * Gebruikt beide 32-bit helften van je 64-bit Assembly output.
 */
unsigned int get_chaos_number (void) {
    static int current_slot = 0;
    static int use_high_bits = 1;
    static uint64_t cached_val = 0;

    if (!use_high_bits) {
        // Wacht tot de service de vlag op -1 zet (data gereed)
        while (shm_base[current_slot].vlag != (uint64_t)-1) {
            __builtin_ia32_pause(); 
        }

        cached_val = shm_base[current_slot].data;
        unsigned int low_bits = (unsigned int)(cached_val & 0xFFFFFFFF);
        use_high_bits = 1;
        return low_bits;
    } else {
        unsigned int high_bits = (unsigned int)(cached_val >> 32);
        
        // Geef slot terug aan de service
        shm_base[current_slot].vlag = 0;
        current_slot = (current_slot + 1) % NUM_SLOTS;
        use_high_bits = 0;
        return high_bits;
    }
}

int main (void) {
    int fd = open(SHM_PATH, O_RDWR);
    if (fd < 0) {
        perror("SHM open failed");
        return 1;
    }

    shm_base = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (shm_base == MAP_FAILED) {
        perror("mmap failed");
        close(fd);
        return 1;
    }

    /* Maak TestU01 generator object */
    unif01_Gen *gen = unif01_CreateExternGenBits("Asm-MT64-Chaos", get_chaos_number);

    printf("--- STARTING BIGCRUSH TEST ON ASM-SERVICE ---\n");
    printf("Testing all bits (split 64-to-32)...\n");
    
    bbattery_BigCrush(gen);

    unif01_DeleteExternGenBits(gen);
    munmap(shm_base, 4096);
    close(fd);
    return 0;
}