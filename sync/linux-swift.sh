#!/usr/bin/env bash
# Wrap `swift` with the C++ include/lib flags BoringSSL needs on Debian/Ubuntu.
# Usage: ./sync/linux-swift.sh test
set -euo pipefail

flags=()

gxx_major=""
if command -v g++ >/dev/null 2>&1; then
  gxx_major=$(g++ -dumpversion | cut -d. -f1)
fi

pick_cxx_dir() {
  local root="$1"
  local preferred="$2"
  if [[ ! -d "${root}" ]]; then
    echo ""
    return
  fi
  if [[ -n "${preferred}" && -d "${root}/${preferred}" ]]; then
    echo "${root}/${preferred}"
    return
  fi
  local newest="" newest_ver=-1
  local d base
  while IFS= read -r d; do
    base=$(basename "${d}")
    [[ "${base}" =~ ^[0-9]+$ ]] || continue
    if [[ "${base}" -gt "${newest_ver}" ]]; then
      newest_ver="${base}"
      newest="${d}"
    fi
  done < <(find "${root}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  echo "${newest}"
}

cxx_inc=$(pick_cxx_dir /usr/include/c++ "${gxx_major}")
cxx_abi=$(pick_cxx_dir /usr/include/x86_64-linux-gnu/c++ "${gxx_major}")
gcc_lib=""
if [[ -n "${gxx_major}" && -d "/usr/lib/gcc/x86_64-linux-gnu/${gxx_major}" ]]; then
  gcc_lib="/usr/lib/gcc/x86_64-linux-gnu/${gxx_major}"
else
  gcc_lib=$(pick_cxx_dir /usr/lib/gcc/x86_64-linux-gnu "")
fi

if [[ -n "${cxx_inc}" ]]; then
  flags+=(-Xcc "-I${cxx_inc}")
fi
if [[ -n "${cxx_abi}" ]]; then
  flags+=(-Xcc "-I${cxx_abi}")
fi
if [[ -n "${gcc_lib}" ]]; then
  flags+=(-Xlinker "-L${gcc_lib}")
fi
flags+=(-Xlinker -lstdc++)

exec swift "$@" "${flags[@]}"
