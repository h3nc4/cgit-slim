# cgit slim

A scratch-built container featuring cgit, nginx, and a git mirror synchronization daemon.

## Usage

Create a `repos.list` file containing repository URLs:

```text
https://git.zx2c4.com/cgit.git
git@github.com:you/your-private-repo.git
```

Run the container:

```bash
docker run -d \
  -p 8080:80 \
  -v $(pwd)/repos.list:/etc/cgit/repos.list:ro \
  -v git-data:/var/lib/git \
  h3nc4/cgit-slim
```

## Configuration

### Environment Variables

| Variable        | Default                | Description                          |
| --------------- | ---------------------- | ------------------------------------ |
| `SYNC_INTERVAL` | `3600`                 | Synchronization interval in seconds. |
| `REPO_LIST`     | `/etc/cgit/repos.list` | Path to the repository list file.    |
| `GIT_ROOT`      | `/var/lib/git`         | Storage path for git repositories.   |

### Volumes

| Path                   | Description                                   |
| ---------------------- | --------------------------------------------- |
| `/var/lib/git`         | Persistent storage for mirrored repositories. |
| `/etc/cgit/repos.list` | Input file listing repositories to mirror.    |
| `/etc/cgitrc`          | Optional override for cgit configuration.     |
| `/run/.ssh`            | Optional directory for SSH keys.              |

### SSH Access

For private repositories using SSH, mount your keys under `/run/.ssh`:

```bash
-v /path/to/ssh-keys/id_ed25519:/run/.ssh/id_ed25519:ro \
```

Ensure the directory is readable by UID `1000`.

## License

cgit slim is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

cgit slim is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with cgit slim. If not, see <https://www.gnu.org/licenses/>.
