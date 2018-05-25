#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <string.h>
#include <unistd.h>
#define CORES 36
struct TASK_RUNNING {
  pid_t tid;
  int cpu;
};

struct TASK_RUNNING task_run[100];
int index_task_run = 0;
int CPUs[CORES];
int CPUs_index = 0;
const char *program;

int index_PS = 0;
// Added latest to check already running threads  on CPUs
void PS(void) {
  char cmd[1024];

  snprintf(cmd, sizeof cmd, "ps -T -u %s,root", getlogin());
  index_task_run = 0;
  // read PS_OUT to get information about current running processes
  FILE *fp = popen(cmd, "r");
  char g;

  // skip the first line
  while ((g = fgetc(fp)) != EOF) {
    // fseek(fp,-1,SEEK_CUR);
    if (g == '\n')
      break;
  }

  while ((g = fgetc(fp)) != EOF) {
    fseek(fp, -1, SEEK_CUR);
    char string[100];
    fgets(string, 100, fp);

    pid_t pid = 0;
    pid_t tid = 0;
    int flag = 0, flag2 = 0;

    char cmd[1000];
    int cmd_index = 0;
    int block = 0;
    int i;
    // printf("%s",string);
    for (i = 0; i < strlen(string); i++) {

      if (flag == 0) {
        if (string[i] >= '0' && string[i] <= '9') {
          pid = pid * 10 + (string[i] - 48);
          flag2 = 1;
        }
      }

      if (flag2 == 1 && string[i] == ' ') {
        flag = 2;
        continue;
      }

      if (flag == 2) {
        if (string[i] >= '0' && string[i] <= '9') {
          tid = tid * 10 + (string[i] - 48);
          flag2 = 3;
        }
      }

      if (flag2 == 3 && string[i] == ' ') {
        flag = 4;
        // printf("PID:%d TID:%d\n",pid,tid);
        continue;
      }

      if (flag == 4) { // printf("Block:%d %c\n",block,string[i]);

        if (string[i] == ':') {
          block++;
          continue;
        }

        if (block == 2) {
          i = i + 2;
          block = 3;
        }

        if (block == 3) {
          if (string[i] == '\n')
            break;

          cmd[cmd_index++] = string[i];
          cmd[cmd_index] = '\0';

          // if(string[i]=='\n')
          // break;
        }
      }

    } // for close

    if (strcmp(&cmd[1], program) == 0) {
      printf("TID:%d CMD:%s Len:%d\n", tid, cmd, strlen(cmd));
      Schedule(tid, 0);
    }
  } // while close

  fclose(fp);
} // function close

void Schedule(pid_t tid, int core) {

  cpu_set_t set;
  CPU_ZERO(&set);
  CPU_SET(CPUs[index_PS], &set);
  if (sched_setaffinity(tid, sizeof(set), &set) != -1) {
    printf("Set TID:%d to CPU:%d\n", tid, CPUs[index_PS]);
    index_PS++;
  } else
      perror("sched_setaffinity");
}

void init_CPUs(void) {
  CPUs_index = 0;
  int i;
  int count = 0;

  /*
     for(i=0;i<CORES;i++)
     {
     CPUs[i]=i;
     }
     */

  for (i = 0; i < CORES / 4; i++) {
    CPUs[i] = count;
    count = count + 2;
  }

  count = 1;
  for (i = CORES / 4; i < CORES / 2; i++) {
    CPUs[i] = count;
    count = count + 2;
  }
  count = CORES / 2;

  for (i = CORES / 2; i < 3 * CORES / 4; i++) {
    CPUs[i] = count;
    count = count + 2;
  }

  count = CORES / 2 + 1;
  for (i = 3 * CORES / 4; i < CORES; i++) {
    CPUs[i] = count;
    count = count + 2;
  }

  index_PS = 0;
}

int main(int argc, char *argv[]) {
  if (argc < 2) {
      fprintf(stderr, "Usage: %s <program>\n", argv[0]);
      return 1;
  }

  program = argv[1];

  while (1) {
    init_CPUs();
    PS();
    sleep(1);
  }

  return 0;
}
