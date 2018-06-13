/**
 * Authors:
 *  Sayak Chakraborti
 *  Princeton Ferro
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/sysinfo.h>
#include <stdbool.h>
#include <stdlib.h>
#include <signal.h>
#include <math.h>
#include <sys/types.h>
#include <pwd.h>
#include <assert.h>

#define MAX(a,b) ((a) > (b) ? (a) : (b))

#define MAX_THREADS 1024
#define MAX_SOCKETS 8
#define MAX_CORES   1024
#define MAX_HYPERTHREADS    4

#define SCHED_DEFAULT_PREFIX    "default:"

enum sched_policy {
    SCHED_COLOCATED,
    SCHED_COLOCATED_HYPERTHREADS,
    SCHED_SPREAD,
    N_DEFAULT_SCHEDULES, 
};

const char *sched_names[] = {
    [SCHED_COLOCATED] = SCHED_DEFAULT_PREFIX"colocated",
    [SCHED_COLOCATED_HYPERTHREADS] = SCHED_DEFAULT_PREFIX"colocated2",
    [SCHED_SPREAD] = SCHED_DEFAULT_PREFIX"spread"
};

struct cpu_info {
  int core_id;
  int sock_id;
};

/* flat list of CPUs */
struct cpu_info cpus[MAX_THREADS];
int num_cpus;

struct cpu_core {
    int pus[MAX_HYPERTHREADS];
    int size;
    int occupancy;
};

struct cpu_socket {
    struct cpu_core cores[MAX_CORES];
    int size;
    int occupancy;
};

/* structured list of CPUs */
struct cpu_socket sockets[MAX_SOCKETS];
int num_sockets;

const char *schedule;
const char *program;

int thread_to_socket[MAX_THREADS];
int num_tts;

void quit_handler(int sig) {
  printf("%s.\n", strsignal(sig));
  exit(0);
}

int compare_tids(const void *arg1, const void *arg2) {
  return *(pid_t *)arg1 - *(pid_t *)arg2;
}

void Schedule(int t, pid_t tid, int sock_id, int core_id, int ht);

const char *get_username(void) {
    char *uname;

    if ((uname = getlogin()))
        return uname;
    else {
        struct passwd *pwd = getpwuid(geteuid());
        if (pwd)
            uname = pwd->pw_name;
    }

    return uname;
}

// Added latest to check already running threads  on CPUs
void PS(void) {
  char cmd[1024];

  snprintf(cmd, sizeof cmd, "ps -T -u %s,root", get_username());
  // read PS_OUT to get information about current running processes
  FILE *fp = popen(cmd, "r");
  char g;

  // skip the first line
  while ((g = fgetc(fp)) != EOF) {
    // fseek(fp,-1,SEEK_CUR);
    if (g == '\n')
      break;
  }

  pid_t threads[MAX_THREADS];
  int num_threads = 0;

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

    if (strncmp(&cmd[1], program, strlen(&cmd[1])) == 0) {
      threads[num_threads++] = tid;
    }
  } // while close

  pclose(fp);

  qsort(threads, num_threads, sizeof threads[0], &compare_tids);

  /* restart packing positions */
  for (int s = 0; s < num_sockets; ++s) {
      for (int c = 0; c < sockets[s].size; ++c)
          sockets[s].cores[c].occupancy = 0;
      sockets[s].occupancy = 0;
  }

  if (strncmp(schedule, SCHED_DEFAULT_PREFIX, strlen(SCHED_DEFAULT_PREFIX)) != 0) {
      for (int t = 0; t < num_threads; ++t) {
        Schedule(t, threads[t], thread_to_socket[t], -1, -1);
      }
  } else { // use an internal schedule
      if (strcmp(schedule, sched_names[SCHED_COLOCATED]) == 0) {
          if (num_threads >= num_cpus) {
              for (int t = 0; t < num_threads; ++t) {
                  int sock_id = floor(t / ((double)num_threads / num_sockets));
                  Schedule(t, threads[t], sock_id, -1, -1);
              }
          } else {
              /**
               * We can give each thread its own hardware context.
               */
              int t = 0;
              for (int s = 0; s < num_sockets && t < num_threads; ++s) {
                  for (int c = 0; c < sockets[s].size && t < num_threads; ++c) {
                      for (int h = 0; h < sockets[s].cores[c].size && t < num_threads; ++h) {
                          Schedule(t, threads[t], s, c, h);
                          ++t;
                      }
                  }
              }
          }
      } else if (strcmp(schedule, sched_names[SCHED_SPREAD]) == 0) {  // spread
          for (int t = 0; t < num_threads; ++t) {
              Schedule(t, threads[t], t % num_sockets, -1, -1);
          }
      } else {  // colocated onto cores first before hyperthreads
          int t = 0;
          while (t < num_threads) {
              for (int s = 0; s < num_sockets && t < num_threads; ++s) {
                  for (int c = 0; c < sockets[s].size && t < num_threads; ++c) {
                      Schedule(t, threads[t], s, c, -1);
                      ++t;
                  }
              }
          }
      }
  }
} // function close

void Schedule(int t, pid_t tid, int sock_id, int core_id, int ht) {
  assert(sock_id >= 0 && sock_id < num_sockets);

  if (core_id == -1)
      core_id = sockets[sock_id].occupancy;

  assert(core_id >= 0 && core_id < sockets[sock_id].size);

  if (ht == -1)
      ht = sockets[sock_id].cores[core_id].occupancy;

  assert(ht >= 0 && ht < sockets[sock_id].cores[core_id].size);

  int cpu = sockets[sock_id].cores[core_id].pus[ht];
  cpu_set_t set;
  CPU_ZERO(&set);
  CPU_SET(cpu, &set);
  if (sched_setaffinity(tid, sizeof set, &set) != -1) {
      printf("Set thread #%d (%d) to CPU %d (socket%d/core%d/hyperthread#%d)\n",
              t, tid, cpu, sock_id, core_id, ht);

      ht = (ht + 1) % sockets[sock_id].cores[core_id].size;
      sockets[sock_id].cores[core_id].occupancy = ht;
      if (ht == 0) {
          // increment core_id
          core_id = (core_id + 1) % sockets[sock_id].size;
          sockets[sock_id].occupancy = core_id;
      }
  } else {
      fprintf(stderr, "Failed to move thread #%d (%d) to CPU %d: %s\n",
              t, tid, cpu, strerror(errno));
  }
}

const struct cpu_info *get_cpu(int i) {
  static struct cpu_info info;
  FILE *fp = NULL;
  char path[1024];

  snprintf(path, sizeof path, "/sys/devices/system/cpu/cpu%d/topology/core_id",
           i);

  if ((fp = fopen(path, "r"))) {
    fscanf(fp, "%d", &info.core_id);
    fclose(fp);
  } else
    return NULL;

  snprintf(path, sizeof path,
           "/sys/devices/system/cpu/cpu%d/topology/physical_package_id", i);
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

  for (int i = 0; i < nprocs && (ci = get_cpu(i)); ++i) {
    cpus[i] = *ci;
    num_cpus = i + 1;
  }

  if (num_cpus != nprocs) {
      perror("fopen");
      abort();
  }

  struct list {
      int items[MAX_THREADS];
      int size;
  };

  struct list socks[MAX_SOCKETS];

  // group into sockets
  for (int i = 0; i < num_cpus; ++i) {
      int len = socks[cpus[i].sock_id].size++;
      socks[cpus[i].sock_id].items[len] = i;
      num_sockets = MAX(cpus[i].sock_id+1, num_sockets);
      assert(num_sockets < MAX_SOCKETS);
  }

  // group into cores
  for (int s = 0; s < num_sockets; ++s) {
      for (int i = 0; i < socks[s].size; ++i) {
          int i2 = socks[s].items[i];   // cpu number
          int len = sockets[s].cores[cpus[i2].core_id].size++;
          sockets[s].cores[cpus[i2].core_id].pus[len] = i2;
          sockets[s].size = MAX(cpus[i2].core_id +1, sockets[s].size);
          assert(sockets[s].size < MAX_CORES);
          assert(sockets[s].cores[cpus[i2].core_id].size < MAX_HYPERTHREADS);
      }
  }
}

bool init_schedule(void) {
  FILE *fp;
  
  if (strncmp(schedule, SCHED_DEFAULT_PREFIX, strlen(SCHED_DEFAULT_PREFIX)) == 0) {
    for (int i = 0; i < N_DEFAULT_SCHEDULES; ++i)
        if (strcmp(schedule, sched_names[i]) == 0)
            return true;
    fprintf(stderr, "Unknown internal schedule '%s'.\n", schedule);
    return false;
  }

  bool ret = true;
  int lineno = 1;
  if ((fp = fopen(schedule, "r"))) {
    int thread, socket;
    while (fscanf(fp, "%d %d ", &thread, &socket) == 2) {
      if (thread >= num_cpus) {
        fprintf(stderr, "%s @ line %d: thread ID must be < num_cpus\n",
                schedule, lineno);
        break;
      }
      if (socket >= num_sockets) {
        fprintf(stderr, "%s @ line %d: socket ID must be < num_sockets\n",
                schedule, lineno);
        break;
      }
      thread_to_socket[thread] = socket;
      num_tts++;
      lineno++;
    }
    if (!feof(fp)) {
      fprintf(stderr, "%s: could not parse line %d", schedule, lineno);
      ret = false;
    }
    fclose(fp);
  } else {
    perror("could not open schedule");
    return false;
  }

  if (num_tts != num_cpus) {
    fprintf(stderr, "needed: %d entries; found: %d\n", num_cpus, num_tts);
    ret = false;
  }

  return ret;
}

int main(int argc, char *argv[]) {
  if (argc < 3) {
    fprintf(stderr, "Usage: %s <program> <schedule>\n", argv[0]);
    return 1;
  }

  program = argv[1];
  schedule = argv[2];

  signal(SIGTERM, &quit_handler);
  signal(SIGQUIT, &quit_handler);
  signal(SIGINT, &quit_handler);

  init_CPUs();

  if (!init_schedule()) {
    fprintf(stderr, "There was a problem with the schedule. Aborting\n");
    return 1;
  }

  printf("Topology: %d hardware contexts across %d sockets:\n", num_cpus, num_sockets);
  for (int i = 0; i < num_sockets; ++i) {
    printf(" socket %d has %d cores: ", i, sockets[i].size);
    for (int j = 0; j < sockets[i].size; ++j) {
        printf("[");
        for (int k = 0; k < sockets[i].cores[j].size; ++k)
          printf("%d%s", sockets[i].cores[j].pus[k], k == sockets[i].cores[j].size-1 ? "" : " ");
        printf("] ");
    }
    printf("\n");
  }


  while (1) {
    PS();
    sleep(1);
  }

  return 0;
}
