#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/stdio.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
  if (argc != 3) {
    fprintf(stderr, "Usage: plainwire-swap CURRENT_APP STAGED_APP\n");
    return 2;
  }

  struct stat current;
  struct stat staged;
  if (lstat(argv[1], &current) != 0 || lstat(argv[2], &staged) != 0) {
    perror("Plainwire app is missing");
    return 1;
  }
  if (!S_ISDIR(current.st_mode) || !S_ISDIR(staged.st_mode) ||
      current.st_dev != staged.st_dev) {
    fprintf(stderr, "Plainwire swap requires two app directories on one volume.\n");
    return 1;
  }

  if (renameatx_np(AT_FDCWD, argv[1], AT_FDCWD, argv[2], RENAME_SWAP) != 0) {
    perror("Atomic Plainwire swap failed; the existing app is unchanged");
    return 1;
  }
  return 0;
}
