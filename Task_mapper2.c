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

#define MAX_THREADS 1024

#define SCHED_DEFAULT_PREFIX    "default:"

#define SCHED_COLOCATED		SCHED_DEFAULT_PREFIX"colocated"

#define SCHED_SPREAD		SCHED_DEFAULT_PREFIX"spread"

struct cpu_socket {
  int cpus[MAX_THREADS]; // thread number (on this socket) -> CPU number
  int num_cpus;          // = num_cores * threads_per_core
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

int thread_to_socket[MAX_THREADS];
int num_tts;

void quit_handler(int sig) {
  printf("%s.\n", strsignal(sig));
  exit(0);
}

int compare_tids(const void *arg1, const void *arg2) {
  return *(pid_t *)arg1 - *(pid_t *)arg2;
}

void Schedule(int tnum, pid_t tid, int sock_id);

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

  if (strncmp(schedule, SCHED_DEFAULT_PREFIX, strlen(SCHED_DEFAULT_PREFIX)) != 0) {
      for (int t = 0; t < num_threads; ++t) {
        Schedule(t, threads[t], thread_to_socket[t]);
      }
  } else { // use an internal schedule
      if (strcmp(schedule, SCHED_COLOCATED) == 0) {
          if (num_threads >= num_cpus) {
              for (int t = 0; t < num_threads; ++t) {
                  Schedule(t, threads[t], floor(t / ((double)num_threads / num_sockets)));
              }
          } else {
              /**
               * We can give each thread its own hardware context.
               */
              int t = 0;
              for (int s = 0; s < num_sockets && t < num_threads; ++s) {
                  for (int c = 0; c < sockets[s].num_cpus && t < num_threads; ++c) {
                      Schedule(t, threads[t], s);
                      ++t;
                  }
              }
          }
      } else {  // spread
          for (int t = 0; t < num_threads; ++t) {
              Schedule(t, threads[t], t % num_sockets);
          }
      }
  }

  for (int s = 0; s < num_sockets; ++s) {
    /**
     * Schedule threads to the exact same hardware contexts
     * the next time around, by starting off at the same location
     * again.
     */
    sockets[s].cpu = 0;
  }
} // function close

void Schedule(int tnum, pid_t tid, int sock_id) {
  int cpu = sockets[sock_id].cpus[sockets[sock_id].cpu];
  cpu_set_t set;
  CPU_ZERO(&set);
  CPU_SET(cpu, &set);
  if (sched_setaffinity(tid, sizeof set, &set) != -1) {
    printf("Set #%d TID:%d to CPU:%d on socket %d\n", tnum, tid, cpu, sock_id);
    sockets[sock_id].cpu =
        (sockets[sock_id].cpu + 1) % sockets[sock_id].num_cpus;
  } else {
    fprintf(stderr, "Failed to set TID %d to CPU %d: %s\n", tid, cpu,
            strerror(errno));
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

  for (int i = 0; i < num_cpus; ++i) {
    int sock_cpus = sockets[cpus[i].sock_id].num_cpus;
    sockets[cpus[i].sock_id].cpus[sock_cpus] = i;
    sockets[cpus[i].sock_id].num_cpus++;
    num_sockets = cpus[i].sock_id > num_sockets ? cpus[i].sock_id : num_sockets;
  }

  num_sockets++;
}

bool init_schedule(void) {
  FILE *fp;
  
  if (strncmp(schedule, SCHED_DEFAULT_PREFIX, strlen(SCHED_DEFAULT_PREFIX)) == 0) {
    if (strcmp(schedule, SCHED_COLOCATED) == 0
        || strcmp(schedule, SCHED_SPREAD) == 0)
        return true;
    else {
        fprintf(stderr, "Unknown internal schedule '%s'. Options are '%s' and '%s'.\n",
                strchr(schedule, ':') + 1, strchr(SCHED_COLOCATED, ':') + 1,
                strchr(SCHED_SPREAD, ':') + 1);
        return false;
    }
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

  printf("Topology: %d threads across %d sockets:\n", num_cpus, num_sockets);
  for (int i = 0; i < num_sockets; ++i) {
    printf(" socket %d has threads:", i);
    for (int j = 0; j < sockets[i].num_cpus; ++j)
      printf(" %d", sockets[i].cpus[j]);
    printf("\n");
  }


  while (1) {
    PS();
    sleep(1);
  }

  return 0;
}
