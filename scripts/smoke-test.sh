#!/bin/sh
# Copyright (C) 2026  Henrique Almeida
# This file is part of cgit slim.
#
# cgit slim is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# cgit slim is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with cgit slim.  If not, see <https://www.gnu.org/licenses/>.

set -eu

image="${1:?usage: smoke-test.sh <image>}"
port="${port:-8080}"
limit=$((port + 100))

cd "$(dirname "$0")/.."
expect_cgit="$(sed -n 's/^ARG CGIT_VERSION="\([^"]*\)".*/\1/p' Dockerfile)"
expect_git="$(sed -n 's/^ARG GIT_VERSION="\([^"]*\)".*/\1/p' Dockerfile)"

work="$(mktemp -d)"
cid=""

cleanup() {
  set +e
  if [ -n "${cid}" ]; then
    docker rm -f "${cid}" >/dev/null 2>&1
  fi
  rm -rf "${work}"
}
trap cleanup EXIT INT TERM

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=h3nc4 GIT_AUTHOR_EMAIL=me@h3nc4.com
export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}" GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"

cd "${work}"
: >repos.list
mkdir git
git init -q seed
cd seed
echo smoke >README.md
git add README.md
git commit -q -m "smoke seed commit"
cd ..
git clone -q --bare seed git/smoke.git
chmod -R a+rX git

while :; do
  if cid="$(docker run -d --rm -p "${port}:80" \
    -v "${work}/repos.list:/etc/cgit/repos.list:ro" \
    -v "${work}/git:/var/lib/git" "${image}" 2>err)"; then
    break
  fi
  if ! grep -q "port is already allocated" err; then
    cat err >&2
    exit 1
  fi
  port=$((port + 1))
  if [ "${port}" -gt "${limit}" ]; then
    echo "no free port below ${limit}" >&2
    exit 1
  fi
done

url="http://127.0.0.1:${port}"

i=0
while [ "${i}" -lt 30 ]; do
  if curl -fsS -o /dev/null "${url}/"; then
    break
  fi
  i=$((i + 1))
  sleep 1
done

if ! curl -fsS "${url}/" | grep -qF "content='cgit v${expect_cgit}'"; then
  echo "the index does not report cgit v${expect_cgit}" >&2
  exit 1
fi

if ! curl -fsS "${url}/smoke.git/log/" | grep -qF "smoke seed commit"; then
  echo "the log page does not show the seed commit" >&2
  exit 1
fi

got_git="$(docker run --rm --entrypoint /bin/git "${image}" --version)"
if [ "${got_git}" != "git version ${expect_git}" ]; then
  echo "expected git version ${expect_git}, got '${got_git}'" >&2
  exit 1
fi

echo "smoke: cgit v${expect_cgit} served the seed repository, ${got_git}"
