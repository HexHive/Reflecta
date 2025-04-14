#include "mruby.h"
#include "mruby/compile.h"
#include "mruby/error.h"

#include "fuzzir.h"

static mrb_state *mrb = NULL;

void fuzzir_initialize(int *argc, char ***argv) {
  mrb = mrb_open();

  if (*argc == 2) {
    char *input = read_str_from_file((*argv)[1]);
    exit(fuzzir_test_one_input(input, strlen(input)));
  }
}

void fuzzir_finalize() {
  mrb_close(mrb);
}

int fuzzir_test_one_input(const char *data, size_t size) {
  mrb_load_string(mrb, data);

  return mrb_check_error(mrb);
}
