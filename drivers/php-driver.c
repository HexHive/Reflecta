
#include <signal.h>
#include <stdint.h>

#include "fuzzir.h"

extern int fuzzer_do_request_from_buffer(const char *file_name,
                                         const char *data, size_t data_len,
                                         int execute,
                                         void (*before_shutdown)(void));

extern void fuzzer_init_php(const char *extra_ini);

int fuzzir_test_one_input(const char *data, size_t size) {
  int retval =
      fuzzer_do_request_from_buffer("/tmp/fuzzer.php", (const char *)data, size,
                                    /* execute */ 1,
                                    /* before_shutdown */ NULL);

  return retval;
}

void fuzzir_initialize(int *argc, char ***argv) {
  /* Compilation will often trigger fatal errors.
   * Use tracked allocation mode to avoid leaks in that case. */
  putenv("USE_TRACKED_ALLOC=1");

  /* Just like other SAPIs, ignore SIGPIPEs. */
  signal(SIGPIPE, SIG_IGN);

  fuzzer_init_php(NULL);

  if (*argc == 2) {
    char *input = read_str_from_file((*argv)[1]);
    exit(fuzzir_test_one_input(input, strlen(input)));
  }
}

void fuzzir_finalize(void) {}
