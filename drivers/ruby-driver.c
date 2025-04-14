#include "fuzzir.h"

extern void ruby_init();
extern void ruby_init_loadpath();
extern void ruby_finalize();
extern void Init_ext(); // Essential for `require` to work.
extern void rb_call_builtin_inits();
extern void rb_eval_string_protect(const char *str, int *state);

void fuzzir_initialize(int *argc, char ***argv) {
  ruby_init();
  ruby_init_loadpath();
  Init_ext();
  rb_call_builtin_inits();

  if (*argc == 2) {
    char *input = read_str_from_file((*argv)[1]);
    exit(fuzzir_test_one_input(input, strlen(input)));
  }
}

void fuzzir_finalize() {
  ruby_finalize();
}

int fuzzir_test_one_input(const char *data, size_t size) {
  int state = 0;
  rb_eval_string_protect(data, &state);

  return state;
}
