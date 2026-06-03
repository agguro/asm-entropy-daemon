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
 * Deze functie haalt 32 bits op per aanroep.
 * We gebruiken een cache om de volledige 64 bits van de ASM-service te testen.
 */
unsigned int get_chaos_number (void) {
    static int current_slot = 0;
    static int use_high_bits = 1;
    static uint64_t cached_64bit_val = 0;

    // Als we de high bits nog niet hebben teruggestuurd, halen we een nieuw 64-bit getal op
    if (!use_high_bits) {
        // WACHT tot de service dit specifieke slot op -1 zet (Data Ready)
        while (shm_base[current_slot].vlag != (uint64_t)-1) {
            __builtin_ia32_pause(); 
        }

        // Haal de volledige 64 bits op
        cached_64bit_val = shm_base[current_slot].data;
        
        // Stuur de onderste 32 bits terug
        unsigned int low_bits = (unsigned int)(cached_64bit_val & 0xFFFFFFFF);
        use_high_bits = 1;
        return low_bits;
    } else {
        // Stuur de bovenste 32 bits van het reeds opgehaalde getal terug
        unsigned int high_bits = (unsigned int)(cached_64bit_val >> 32);
        
        // NU PAS geven we het slot terug aan de service door de vlag op 0 te zetten
        shm_base[current_slot].vlag = 0;
        
        // Schuif door naar het volgende slot in de ringbuffer
        current_slot = (current_slot + 1) % NUM_SLOTS;
        
        // Reset de toggle voor de volgende aanroep
        use_high_bits = 0;
        return high_bits;
    }
}

int main (void) {
    int fd = open(SHM_PATH, O_RDWR);
    if (fd < 0) {
        perror("Fout: Kon SHM niet openen. Draait de chaos_service?");
        return 1;
    }

    // Map de volledige 4096 bytes (64 slots * 64 bytes)
    shm_base = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (shm_base == MAP_FAILED) {
        perror("mmap mislukt");
        close(fd);
        return 1;
    }

    /* Maak TestU01 generator object */
    unif01_Gen *gen = unif01_CreateExternGenBits("Asm-MT64-Chaos", get_chaos_number);

    printf("--- STARTING THE SMALLCRUSH BATTLE - ASM MT64 vs TESTU01 ---\n");
    printf("Mapping: 64 slots, split-phase 32-bit consumption.\n\n");

    // Start de batterij
    bbattery_SmallCrush(gen);

    // Netjes opruimen
    unif01_DeleteExternGenBits(gen);
    munmap(shm_base, 4096);
    close(fd);
    
    printf("\nTest sessie voltooid.\n");
    return 0;
}