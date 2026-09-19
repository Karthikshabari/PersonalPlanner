#!/usr/bin/env bash
#
# Registers Personal Planner as the desktop handler for its own callback URIs.
#
# Without this registration a Linux browser cannot hand
#   com.personalplanner.personalplanner://login-callback      (email confirmation)
#   com.personalplanner.personalplanner://management-callback (Supabase authorization)
# to the application, and the user is left on an unknown-scheme page.
#
# Usage:
#   linux/packaging/register_uri_scheme.sh [path-to-personal_planner]
#
# With no argument the script looks for the release bundle next to this
# repository (build/linux/x64/release/bundle/personal_planner) and then for
# `personal_planner` on PATH. It installs a per-user desktop entry, so nothing
# outside $XDG_DATA_HOME is modified.
set -euo pipefail

scheme="x-scheme-handler/com.personalplanner.personalplanner"
desktop_id="personal_planner.desktop"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "${script_dir}/../.." && pwd)"

executable="${1:-}"
if [[ -z "${executable}" ]]; then
  for candidate in \
    "${repository_root}/build/linux/x64/release/bundle/personal_planner" \
    "${repository_root}/build/linux/arm64/release/bundle/personal_planner"; do
    if [[ -x "${candidate}" ]]; then
      executable="${candidate}"
      break
    fi
  done
fi
if [[ -z "${executable}" ]]; then
  executable="$(command -v personal_planner || true)"
fi
if [[ -z "${executable}" || ! -x "${executable}" ]]; then
  echo "Personal Planner executable not found. Pass its path as the first argument." >&2
  exit 1
fi
executable="$(readlink -f "${executable}")"

data_home="${XDG_DATA_HOME:-${HOME}/.local/share}"
applications_dir="${data_home}/applications"
mkdir -p "${applications_dir}"

sed "s|^Exec=personal_planner$|Exec=${executable}|" \
  "${script_dir}/personal_planner.desktop" > "${applications_dir}/${desktop_id}"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${applications_dir}" >/dev/null 2>&1 || true
fi
if command -v xdg-mime >/dev/null 2>&1; then
  xdg-mime default "${desktop_id}" "${scheme}"
fi

echo "Registered ${desktop_id} as the handler for ${scheme}."
echo "Executable: ${executable}"
