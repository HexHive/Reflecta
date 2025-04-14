#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define error(fmt, ...)                                                        \
  fprintf(stderr, "[!] (%s:%d) " fmt, __FILE__, __LINE__, ##__VA_ARGS__);      \
  exit(1);

#define error_if(cond, fmt, ...)                                               \
  if (cond) {                                                                  \
    error("[!] (%s:%d) " fmt, __FILE__, __LINE__, ##__VA_ARGS__);              \
  }

#define info(fmt, ...)                                                         \
  fprintf(stderr, "[*] (%s:%d) " fmt, __FILE__, __LINE__, ##__VA_ARGS__);

#define debug(fmt, ...)                                                        \
  if (getenv("FUZZIR_DEBUG") != NULL) {                                        \
    fprintf(stderr, "[~] (%s:%d) " fmt, __FILE__, __LINE__, ##__VA_ARGS__);    \
  }

/* FuzzIR Interface */
void fuzzir_initialize(int *argc, char ***argv);
void fuzzir_finalize();
int fuzzir_test_one_input(const char *data, size_t size);

static char *copy_to_static_buf(const char *data, size_t size) {
  static char buf[0x10000];

  if (size > 0x10000) {
    *buf = 0;
  } else {
    memcpy(buf, data, size);
  }

  return buf;
}

static char *read_str_from_file(char *filename) {
  static char buf[0x10000];

  FILE *fp = fopen(filename, "r");
  error_if(fp == NULL, "Failed to open file: %s\n", filename);

  fseek(fp, 0, SEEK_END);
  size_t size = ftell(fp);
  rewind(fp);
  error_if(size > 0x10000, "File too large: %s\n", filename);

  size_t read_size = fread(buf, 1, size, fp);
  error_if(read_size != size, "Failed to read file: %s\n", filename);

  buf[size] = '\0';
  fclose(fp);

  return buf;
}

static char *read_str_from_stdin() {
  static char buf[0x10000];

  memset(buf, 0, sizeof(buf));
  read(0, buf, sizeof(buf) - 1);

  return buf;
}

static const char *next_line(const char *src) {
  while (*src != '\n' && *src != '\0') {
    src++;
  }

  return src + 1;
}

static char *indent_input(const char *input, size_t size) {
  static char buf[0x10000];
  static char indent[] = "    ";

  int level = 0, indent_len = sizeof(indent) - 1;
  char *dst = buf, *buf_last = buf + sizeof(buf) - 1;
  const char *src = input;

  while (src < input + size) {
    const char *next = next_line(src);
    int inc = next - src;

    if (strncmp(src, "INDENT", 6) == 0) {
      level++;
    } else if (strncmp(src, "DEDENT", 6) == 0) {
      level--;
    } else {
      if (dst + level * indent_len + inc >= buf_last) {
        *buf = '\0';
        return buf;
      }

      for (int i = 0; i < level; i++, dst += indent_len) {
        memcpy(dst, indent, indent_len);
      }

      memcpy(dst, src, inc);
      dst += inc;
    }

    src = next;
  }

  *dst = '\0';
  debug("\n%s\n", buf);

  return buf;
}
