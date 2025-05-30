#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

//
// BEGIN FUZZING CODE
//

#define REPRL_CRFD 100
#define REPRL_CWFD 101
#define REPRL_DRFD 102
#define REPRL_DWFD 103

#define SHM_SIZE 0x100000
#define MAX_EDGES ((SHM_SIZE - 4) * 8)

#define EARLY_EXIT 1
#define EXIT(ret)                                                              \
  if (EARLY_EXIT) {                                                            \
    _exit(ret);                                                                \
  }

#define CHECK(cond)                                                            \
  if (!(cond)) {                                                               \
    fprintf(stderr, "\"" #cond "\" failed\n");                                 \
    EXIT(-1);                                                                  \
  }

struct shmem_data {
  uint32_t num_edges;
  unsigned char edges[];
};

struct shmem_data *__shmem;
uint32_t *__edges_start, *__edges_stop;

void __sanitizer_cov_reset_edgeguards() {
  uint64_t N = 0;
  for (uint32_t *x = __edges_start; x < __edges_stop && N < MAX_EDGES; x++)
    *x = ++N;
}

static bool init = false;
void __sanitizer_cov_trace_pc_guard_init(uint32_t *start, uint32_t *stop) {
  init = true;
  // Avoid duplicate initialization
  if (start == stop || *start)
    return;

  if (__edges_start != NULL || __edges_stop != NULL) {
    fprintf(stderr, "Found new module with length: %lu. Skipping\n",
            stop - start);
    return;
    // EXIT(-1);
  }

  __edges_start = start;
  __edges_stop = stop;

  // Map the shared memory region
  const char *shm_key = getenv("SHM_ID");
  if (!shm_key) {
    fprintf(stderr, "[COV] no shared memory bitmap available, skipping\n");
    __shmem = (struct shmem_data *)malloc(SHM_SIZE);
  } else {
    int fd = shm_open(shm_key, O_RDWR, S_IREAD | S_IWRITE);
    if (fd <= -1) {
      fprintf(stderr, "Failed to open shared memory region: %s\n",
              strerror(errno));
      EXIT(-1);
    }

    __shmem = (struct shmem_data *)mmap(0, SHM_SIZE, PROT_READ | PROT_WRITE,
                                        MAP_SHARED, fd, 0);
    if (__shmem == MAP_FAILED) {
      fprintf(stderr, "Failed to mmap shared memory region\n");
      EXIT(-1);
    }
  }

  __sanitizer_cov_reset_edgeguards();

  __shmem->num_edges = stop - start;
  fprintf(stderr,
          "[COV] edge counters initialized. Shared memory: %s with %u edges\n",
          shm_key, __shmem->num_edges);
}

void __sanitizer_cov_trace_pc_guard(uint32_t *guard) {
  if (!init) {
    return;
  }
  // There's a small race condition here: if this function executes in two
  // threads for the same edge at the same time, the first thread might disable
  // the edge (by setting the guard to zero) before the second thread fetches
  // the guard value (and thus the index). However, our instrumentation ignores
  // the first edge (see libcoverage.c) and so the race is unproblematic.
  uint32_t index = *guard;
  // If this function is called before coverage instrumentation is properly
  // initialized we want to return early.
  if (!index)
    return;
  __shmem->edges[index / 8] |= 1 << (index % 8);
  *guard = 0;
}

//
// END FUZZING CODE
//
