/* Copyright (C) 2026  Henrique Almeida
 * This file is part of cgit-slim.
 *
 * cgit-slim is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * cgit-slim is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with cgit-slim.  If not, see <https://www.gnu.org/licenses/>.
 */

#define _POSIX_C_SOURCE 200809L

#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define DEFAULT_LIST_FILE "/etc/cgit/repos.list"
#define DEFAULT_GIT_DIR "/var/lib/git"
#define DEFAULT_INTERVAL 3600
#define BIN_GIT "/bin/git"

#define ENV_REPO_LIST "REPO_LIST"
#define ENV_GIT_ROOT "GIT_ROOT"
#define ENV_INTERVAL "SYNC_INTERVAL"

void
log_msg (const char *msg, const char *arg)
{
  time_t now;
  time (&now);
  char buf[26];
  struct tm *tm_info = localtime (&now);
  strftime (buf, 26, "%Y-%m-%d %H:%M:%S", tm_info);
  if (arg)
    {
      printf ("[%s] %s %s\n", buf, msg, arg);
    }
  else
    {
      printf ("[%s] %s\n", buf, msg);
    }
  fflush (stdout);
}

void
run_git (char *const argv[])
{
  pid_t pid = fork ();
  if (pid < 0)
    {
      perror ("fork");
      return;
    }
  if (pid == 0)
    {
      execv (BIN_GIT, argv);
      perror ("execv git");
      exit (1);
    }
  int status;
  waitpid (pid, &status, 0);
}

void
configure_safe_directory (void)
{
  char *argv[]
      = { "git", "config", "--global", "--add", "safe.directory", "*", NULL };
  run_git (argv);
}

int
get_sync_interval (void)
{
  const char *val = getenv (ENV_INTERVAL);
  if (val)
    {
      int interval = atoi (val);
      if (interval > 0)
        {
          return interval;
        }
      log_msg ("Invalid SYNC_INTERVAL, using default", NULL);
    }
  return DEFAULT_INTERVAL;
}

const char *
get_list_file (void)
{
  const char *val = getenv (ENV_REPO_LIST);
  return val ? val : DEFAULT_LIST_FILE;
}

const char *
get_git_dir (void)
{
  const char *val = getenv (ENV_GIT_ROOT);
  return val ? val : DEFAULT_GIT_DIR;
}

int
main (void)
{
  const char *list_file = get_list_file ();
  const char *git_dir = get_git_dir ();
  int interval = get_sync_interval ();

  if (access (list_file, F_OK) != 0)
    {
      log_msg ("No repo list found at", list_file);
      return 0;
    }

  configure_safe_directory ();

  while (1)
    {
      log_msg ("Starting cgit sync", NULL);

      FILE *fp = fopen (list_file, "r");
      if (!fp)
        {
          perror ("fopen");
          sleep (interval);
          continue;
        }

      char *line = NULL;
      size_t len = 0;
      ssize_t read_len;

      while ((read_len = getline (&line, &len, fp)) != -1)
        {
          if (line[read_len - 1] == '\n')
            {
              line[read_len - 1] = '\0';
            }
          if (line[0] == '\0' || line[0] == '#')
            {
              continue;
            }

          char *repo_url = line;
          char *url_copy = strdup (repo_url);
          if (!url_copy)
            {
              continue;
            }

          char *base = basename (url_copy);
          char *dot = strrchr (base, '.');
          if (dot && strcmp (dot, ".git") == 0)
            {
              *dot = '\0';
            }

          char target[2048];
          snprintf (target, sizeof (target), "%s/%s", git_dir, base);

          struct stat st;
          if (stat (target, &st) == 0 && S_ISDIR (st.st_mode))
            {
              log_msg ("Updating", base);
              char *argv[] = { "git",    "-C",      target, "remote",
                               "update", "--prune", NULL };
              run_git (argv);
            }
          else
            {
              log_msg ("Cloning", base);
              char *argv[] = { "git",    "clone", "-4", "--mirror",
                               repo_url, target,  NULL };
              run_git (argv);
            }
          free (url_copy);
        }

      free (line);
      fclose (fp);

      char msg[64];
      snprintf (msg, sizeof (msg), "Sync finished. Sleeping for %d seconds...",
                interval);
      log_msg (msg, NULL);
      sleep (interval);
    }
  return 0;
}
