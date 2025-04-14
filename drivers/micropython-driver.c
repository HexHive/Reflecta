#include "fuzzir.h"

extern void mp_unix_init(int argc, char **argv);
extern void mp_unix_deinit(void);
extern void mp_unix_clear(void);
extern int mp_unix_run_str(const char *str);

void fuzzir_initialize(int *argc, char ***argv) {
  mp_unix_init(*argc, *argv);

  if (*argc == 2) {
    char *input = read_str_from_file((*argv)[1]);
    exit(fuzzir_test_one_input(input, strlen(input)));
  }
}

void fuzzir_finalize() { mp_unix_deinit(); }

int fuzzir_test_one_input(const char *data, size_t size) {
  char *indented = indent_input(data, size);
  mp_unix_clear();

  return mp_unix_run_str(indented);
}

void stateless_test() {
  char *input1 = "a = 1; print(a)\n";
  char *input2 = "a += 1; print(a)\n";
  assert(fuzzir_test_one_input(input1, strlen(input1)) == 0);
  assert(fuzzir_test_one_input(input2, strlen(input2)) == 1);
}

void exception_test() {
  char *input1 = "raise Exception('hello')\n";
  char *input2 = "print('hello')\n";
  assert(fuzzir_test_one_input(input1, strlen(input1)) == 1);
  assert(fuzzir_test_one_input(input2, strlen(input2)) == 0);
}
