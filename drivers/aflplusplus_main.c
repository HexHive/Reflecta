#include <stdio.h>

#include "fuzzir.h"

int main(int argc, char **argv) {
  fuzzir_initialize(&argc, &argv);

#ifdef PERSISTENT
  __AFL_INIT();
  while (__AFL_LOOP(1000))
#endif
  {
    char *input = read_str_from_stdin();
    fuzzir_test_one_input(input, strlen(input));

    fflush(stdout);
    fflush(stderr);
  }

  fuzzir_finalize();

  return 0;
}
