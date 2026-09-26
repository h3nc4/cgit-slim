# cgit slim

A read-only web view of git repositories, on `FROM scratch`. The image contains cgit for the pages, nginx in front of it, and a daemon that mirrors each repository from its upstream.

Point it at a list of repository URLs. It clones each one, refreshes them on a timer and serves them over HTTP. It never pushes, and it serves nothing writable.

## Running it

List the repositories to mirror, one URL per line:

```text
https://git.zx2c4.com/cgit.git
git@github.com:you/your-private-repo.git
```

Then mount that list and give the clones somewhere to live:

```bash
docker run -d \
  -p 8080:80 \
  -v "${PWD}/repos.list:/etc/cgit/repos.list:ro" \
  -v git-data:/var/lib/git \
  h3nc4/cgit-slim
```

nginx listens on port 80 inside the container. The first clone appears at `http://localhost:8080` once the daemon has fetched it. A large repository needs minutes on that first pass, and the page is empty until the clone completes.

## What to mount, and where

Only one of these is a volume. The rest are files and directories the image reads.

| Path | Kind | Purpose |
| --- | --- | --- |
| `/var/lib/git` | volume | The mirrored clones, and the only state a restart has to preserve. |
| `/etc/cgit/repos.list` | file, read-only | The list of upstream URLs. Required. |
| `/etc/cgitrc` | file, read-only | Replaces the built-in cgit configuration. Optional. |
| `/run/.ssh` | directory | Keys and `known_hosts` for SSH remotes. Optional. |

## Settings

| Variable | Default | Meaning |
| --- | --- | --- |
| `SYNC_INTERVAL` | `3600` | Seconds between refresh passes. |
| `REPO_LIST` | `/etc/cgit/repos.list` | Where the URL list is read. |
| `GIT_ROOT` | `/var/lib/git` | Where the clones are kept. |

## Mirroring over SSH

A private repository needs a key. Mount it into `/run/.ssh`, readable by uid 1000, which is the uid the container runs as:

```bash
-v /path/to/id_ed25519:/run/.ssh/id_ed25519:ro \
```

The image contains an SSH config setting `StrictHostKeyChecking accept-new`, against an empty `known_hosts`. So the first connection to a host accepts whatever key it presents and pins it for later. That is trust on first use: it stops a key changing underneath the mirror, and it does nothing about the first connection being intercepted.

Mount a prepared `known_hosts` to decide the key in advance:

```bash
ssh-keyscan github.com > known_hosts
```

```bash
-v "${PWD}/known_hosts:/run/.ssh/known_hosts:ro" \
```

`known_hosts` is written on first contact, so mounting it read-only makes an unknown host an error rather than a silent trust.

## License

<!-- vale off -->

cgit slim is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

cgit slim is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with cgit slim. If not, see <https://www.gnu.org/licenses/>.
