#include <stdbool.h>
#include <stdio.h>

#include "fuzzir.h"

#include "fuzzilli_sancov.c"

static void fuzzilli_hello() {
  char helo[] = "HELO";
  if (write(REPRL_CWFD, helo, 4) != 4 || read(REPRL_CRFD, helo, 4) != 4) {
    fprintf(stderr, "Invalid HELO response from parent\n");
    EXIT(-1);
  }

  if (memcmp(helo, "HELO", 4) != 0) {
    fprintf(stderr, "Invalid response from parent\n");
    EXIT(-1);
  }
}

static void fuzzilli_loop() {
  static char buf[0x10000];

  while (true) {
    size_t script_size = 0, remaining = 0;
    int action, state;

    CHECK(read(REPRL_CRFD, &action, 4) == 4);
    if (action == 'cexe') {
      CHECK(read(REPRL_CRFD, &script_size, 8) == 8);
    } else {
      fprintf(stderr, "Unknown action: %u\n", action);
      EXIT(-1);
    }

    script_size = script_size > sizeof(buf) - 1 ? sizeof(buf) - 1 : script_size;
    remaining = script_size;
    char *ptr = buf;
    while (remaining > 0) {
      ssize_t rv = read(REPRL_DRFD, ptr, remaining);
      if (rv <= 0) {
        fprintf(stderr, "Failed to load script\n");
        EXIT(-1);
      }
      remaining -= rv;
      ptr += rv;
    }

    buf[script_size] = '\0';
    state = fuzzir_test_one_input(buf, script_size);

    fflush(stdout);
    fflush(stderr);

    // Send return code to parent and reset edge counters.
    // Lower 8 bits are reserved for signals?
    int status = (state & 0xff) << 8;
    CHECK(write(REPRL_CWFD, &status, 4) == 4);
    __sanitizer_cov_reset_edgeguards();
  }
}

int main(int argc, char **argv) {
  fuzzir_initialize(&argc, &argv);

  fuzzilli_hello();
  fuzzilli_loop();

  fuzzir_finalize();

  return 0;
}
