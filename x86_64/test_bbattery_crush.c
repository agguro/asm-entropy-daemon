/* =============================================================================
 * Project:      asm-entropy-daemon
 * File:         test_bbattery_crush.c
 * Author:       agguro
 * Date:         August 20, 2026 
 * Description:  TestU01 Crush battery test harness for the Chaos Service.
 *               Bridges the 64-bit Assembly PRNG engine via POSIX shared memory 
 *               into TestU01's 32-bit external generator interface.
 *
 *               NOTE: This file serves as a robust C integration template for 
 *               future test harnesses requiring validation of low-level engines 
 *               via statistical test suites (TestU01 / Crush).
 *
 *   MATHEMATICAL & STRUCTURAL PROPERTIES:
 *   - Bit Splitting: Splits 64-bit quadwords into two sequential 32-bit uints 
 *     to comply with TestU01's unif01_Gen bit-stream expectations.
 *   - Slot Synchronization: Maintains lock-free pacing across the 64 shared memory 
 *     slots using busy-wait flags and explicit cache-line padding (64 bytes/slot).
 *
 * Architecture: x86_64 | Linux C99 | TestU01 1.2.3
 *
 * Copyright 2026 agguro
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 */

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
    uint64_t flag;      /* -1 = Free, 0 = Request Pending */
    uint64_t data;      /* Resulting random number payload */
    uint8_t  padding[48]; /* Padding to exactly 64 bytes for optimal cache-line alignment */
} slot_t;

slot_t *shm_base;

/* =============================================================================
 * Function: get_chaos_number
 * Description: Retrieves 32 bits per call for TestU01 compatibility.
 *              Caches 64-bit values and splits them into high and low halves.
 * =============================================================================
 */
unsigned int get_chaos_number (void) {
    static int current_slot = 0;
    static int use_high_bits = 1;
    static uint64_t cached_64bit_val = 0;

    /* If we have already sent the high bits, fetch a new 64-bit value */
    if (!use_high_bits) {
        /* Wait until the service sets this specific slot flag to -1 (Data Ready) */
        while (shm_base[current_slot].flag != (uint64_t)-1) {
            __builtin_ia32_pause(); 
        }

        /* Retrieve the full 64-bit entropy block from shared memory slot */
        cached_64bit_val = shm_base[current_slot].data;
        
        /* Extract and return the lower 32 bits */
        unsigned int low_bits = (unsigned int)(cached_64bit_val & 0xFFFFFFFF);
        use_high_bits = 1;
        return low_bits;
    } else {
        /* Return the upper 32 bits of the already fetched cached value */
        unsigned int high_bits = (unsigned int)(cached_64bit_val >> 32);
        
        /* Signal the service that the slot is ready for a new request by setting flag to 0 */
        shm_base[current_slot].flag = 0;
        
        /* Move to the next slot in the ring buffer (round-robin 0..63) */
        current_slot = (current_slot + 1) % NUM_SLOTS;
        
        /* Toggle state flag for the subsequent call */
        use_high_bits = 0;
        return high_bits;
    }
}

int main (void) {
    int fd = open(SHM_PATH, O_RDWR);
    if (fd < 0) {
        perror("Error: Could not open SHM. Is the chaos_service running?");
        return 1;
    }

    /* Map the full 4096 bytes (64 slots * 64 bytes per slot) into process space */
    shm_base = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (shm_base == MAP_FAILED) {
        perror("mmap failed");
        close(fd);
        return 1;
    }

    /* Create TestU01 external generator object wrapper */
    unif01_Gen *gen = unif01_CreateExternGenBits("Asm-MT64-Chaos", get_chaos_number);

    printf("--- STARTING THE CRUSH BATTLE - ASM MT64 vs TESTU01 ---\n");
    printf("Mapping: 64 slots, split-phase 32-bit consumption.\n\n");

    /* Execute the standard Crush test battery */
    bbattery_Crush(gen);

    /* Clean up resources */
    unif01_DeleteExternGenBits(gen);
    munmap(shm_base, 4096);
    close(fd);
    
    printf("\nTest session completed.\n");
    return 0;
}
