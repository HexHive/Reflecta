#include "fuzzir.h"

int main() {
    char *input = read_str_from_stdin();
    char *indented = indent_input(input, strlen(input));
    puts(indented);

    return 0;
}
