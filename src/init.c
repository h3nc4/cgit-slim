/* Copyright (C) 2026  Henrique Almeida
 * This file is part of cgit slim.
 *
 * cgit slim is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * cgit slim is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with cgit slim.  If not, see <https://www.gnu.org/licenses/>.
 */

#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define BIN_FCGIWRAP "/bin/fcgiwrap"
#define BIN_SYNC "/bin/mirror-sync"
#define BIN_NGINX "/bin/nginx"
#define SOCKET_FCGI "unix:/run/fcgiwrap.socket"

static pid_t pid_fcgi = -1;
static pid_t pid_sync = -1;
static pid_t pid_nginx = -1;

void
terminate_child (pid_t pid)
{
  if (pid > 0)
    {
      kill (pid, SIGTERM);
    }
}

void
handle_signal (int sig)
{
  (void)sig;
  terminate_child (pid_nginx);
  terminate_child (pid_sync);
  terminate_child (pid_fcgi);
}

pid_t
spawn (const char *cmd, char *const argv[])
{
  pid_t pid = fork ();
  if (pid < 0)
    {
      perror ("fork");
      exit (1);
    }
  if (pid == 0)
    {
      execv (cmd, argv);
      perror ("execv");
      exit (1);
    }
  return pid;
}

int
main (void)
{
  struct sigaction sa;
  sa.sa_handler = handle_signal;
  sigemptyset (&sa.sa_mask);
  sa.sa_flags = 0;
  sigaction (SIGTERM, &sa, NULL);
  sigaction (SIGINT, &sa, NULL);

  // Spawn children
  char *args_fcgi[] = { BIN_FCGIWRAP, "-s", SOCKET_FCGI, NULL };
  pid_fcgi = spawn (args_fcgi[0], args_fcgi);
  char *args_sync[] = { BIN_SYNC, NULL };
  pid_sync = spawn (args_sync[0], args_sync);
  char *args_nginx[] = { BIN_NGINX, NULL };
  pid_nginx = spawn (args_nginx[0], args_nginx);

  // Monitor loop
  int status;
  pid_t exited_pid;

  // Wait for children. If any service exits, the container fails.
  while ((exited_pid = wait (&status)) > 0)
    {
      if (exited_pid == pid_nginx || exited_pid == pid_fcgi
          || exited_pid == pid_sync)
        {
          fprintf (stderr, "Critical process %d exited. Shutting down.\n",
                   exited_pid);
          handle_signal (SIGTERM);
          while (wait (&status) > 0)
            {
              ; // Reap remaining children
            }
          break;
        }
    }

  return 0;
}
