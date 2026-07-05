/* =============================================================================
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 * Author: Aguas Guerreiro Roberto [agguro]
 * Date: 2026-07-05
 * Description: TestU01 SmallCrush battery test for the Chaos Service.
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
    uint64_t data;      /* Resulting random number */
    uint8_t  padding[48]; /* Padding to 64 bytes for cache-line alignment */
} slot_t;

slot_t *shm_base;

/* * This function retrieves 32 bits per call.
 * We use a cache to split the 64-bit Assembly service output into two 32-bit values.
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

        /* Retrieve the full 64 bits */
        cached_64bit_val = shm_base[current_slot].data;
        
        /* Return the lower 32 bits */
        unsigned int low_bits = (unsigned int)(cached_64bit_val & 0xFFFFFFFF);
        use_high_bits = 1;
        return low_bits;
    } else {
        /* Return the upper 32 bits of the already fetched value */
        unsigned int high_bits = (unsigned int)(cached_64bit_val >> 32);
        
        /* Signal the service that the slot is ready for a new request by setting flag to 0 */
        shm_base[current_slot].flag = 0;
        
        /* Move to the next slot in the ring buffer */
        current_slot = (current_slot + 1) % NUM_SLOTS;
        
        /* Toggle state for the next call */
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

    /* Map the full 4096 bytes (64 slots * 64 bytes) */
    shm_base = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (shm_base == MAP_FAILED) {
        perror("mmap failed");
        close(fd);
        return 1;
    }

    /* Create TestU01 generator object */
    unif01_Gen *gen = unif01_CreateExternGenBits("Asm-MT64-Chaos", get_chaos_number);

    printf("--- STARTING THE SMALLCRUSH BATTLE - ASM MT64 vs TESTU01 ---\n");
    printf("Mapping: 64 slots, split-phase 32-bit consumption.\n\n");

    /* Execute the test battery */
    bbattery_SmallCrush(gen);

    /* Clean up */
    unif01_DeleteExternGenBits(gen);
    munmap(shm_base, 4096);
    close(fd);
    
    printf("\nTest session completed.\n");
    return 0;
}