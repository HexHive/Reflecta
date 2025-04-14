#include "fuzzir.h"
#include "python3.10/Python.h"

void fuzzir_initialize(int *argc, char ***argv) {
  Py_Initialize();

  if (*argc == 2) {
    char *input = read_str_from_file((*argv)[1]);
    exit(fuzzir_test_one_input(input, strlen(input)));
  }
}

void fuzzir_finalize() { Py_Finalize(); }

int fuzzir_test_one_input(const char *data, size_t size) {
  char *indented = indent_input(data, size);
  // dbgh(indented, size);
  // dbgh(data, size);
  // assert(strncmp(indented, data, size) == 0);

  PyObject *dict = PyDict_New();
  PyDict_SetItemString(dict, "__builtins__", PyEval_GetBuiltins());
  PyObject *ret = PyRun_String(indented, Py_file_input, dict, dict);
  PyErr_Clear();
  Py_DECREF(dict);

  return !ret;
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
