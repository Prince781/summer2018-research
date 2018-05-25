#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/sysinfo.h>

#define MAX_THREADS 1024

struct cpu_socket {
    int cpus[MAX_THREADS];   // thread number (on this socket) -> CPU number
    int num_cpus;   // = num_cores * threads_per_core
    int cpu;
};

struct cpu_socket sockets[MAX_THREADS];

int num_sockets;

struct cpu_info {
    int core_id;
    int sock_id;
};

struct cpu_info cpus[MAX_THREADS];
int num_cpus;

const char *schedule;
const char *program;

int index_PS = 0;
// Added latest to check already running threads  on CPUs
void PS(void) {
  char cmd[1024];

  snprintf(cmd, sizeof cmd, "ps -T -u %s,root", getlogin());
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

  pclose(fp);
} // function close

void Schedule(pid_t tid, int sock_id) {
  int cpu = sockets[sock_id].cpus[sockets[sock_id].cpu];
  cpu_set_t set;
  CPU_ZERO(&set);
  CPU_SET(cpu, &set);
  if (sched_setaffinity(tid, sizeof set, &set) != -1) {
    printf("Set TID:%d to CPU:%d\n", tid, cpu);
    sockets[sock_id].cpu = (sockets[sock_id].cpu+ 1) % sockets[sock_id].num_cpus;
  } else {
      fprintf(stderr, "Failed to set TID %d to CPU %d: %s\n", 
              tid, cpu, strerror(errno));
  }
}

const struct cpu_info *get_cpu(int i) {
    static struct cpu_info info;
    FILE *fp = NULL;
    char path[1024];

    snprintf(path, sizeof path, "/sys/devices/system/cpu/cpu%d/topology/core_id", i);

    if ((fp = fopen(path, "r"))) {
        fscanf(fp, "%d", &info.core_id);
        fclose(fp);
    } else
        return NULL;

    snprintf(path, sizeof path, "/sys/devices/system/cpu/cpu%d/topology/physical_package_id", i);
    if ((fp = fopen(path, "r"))) {
        fscanf(fp, "%d", &info.sock_id);
        fclose(fp);
    } else
        return NULL;

    return &info;
}

void init_CPUs(void) {
    const struct cpu_info *ci;
    int nprocs = get_nprocs();

    for (int i=0; i<nprocs && (ci = get_cpu(i)); ++i) {
        cpus[i] = *ci;
        num_cpus = i+1;
    }

    for (int i=0; i<num_cpus; ++i) {
        int sock_cpus = sockets[cpus[i].sock_id].num_cpus;
        sockets[cpus[i].sock_id].cpus[sock_cpus] = i;
        sockets[cpus[i].sock_id].num_cpus++;
        num_sockets = cpus[i].sock_id > num_sockets ? cpus[i].sock_id : num_sockets;
    }

    num_sockets++;
}

void init_schedule(void) {
}

int main(int argc, char *argv[]) {
  if (argc < 3) {
      fprintf(stderr, "Usage: %s <program> <schedule>\n", argv[0]);
      return 1;
  }

  program = argv[1];
  schedule = argv[2];

  init_CPUs();

  printf("Topology: %d threads across %d sockets:\n", num_cpus, num_sockets);
  for (int i=0; i<num_sockets; ++i) {
      printf(" socket %d has threads:", i);
      for (int j=0; j<sockets[i].num_cpus; ++j)
          printf(" %d", sockets[i].cpus[j]);
      printf("\n");
  }

  init_schedule();

  while (1) {
    PS();
    sleep(1);
  }

  return 0;
}
