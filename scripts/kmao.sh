#!/usr/bin/env bash
# WSL entry point. Windows paths are passed as arguments, never evaluated as code.
set -euo pipefail

usage() {
    cat <<'HELP'
Usage: ./scripts/kmao.sh <doctor|test|keygen|build|export> [options]

  doctor  Show Windows PowerShell and Inno Setup availability.
  test    Run core, update and session tests in Windows PowerShell 5.1.
  keygen  Create signing keys in the Windows user's .kmao-signing directory.
  build   Build signed release files and the Windows installer.
  export  Create the portable folder and ZIP.

Options (paths use Linux/WSL notation, including /mnt/c/...):
  --private-key PATH   Override the Windows-profile private key (keygen/build).
  --public-key PATH    Override the Windows-profile public key (keygen/build).
  --output PATH        Output directory (build/export).
  --iscc PATH          Windows ISCC.exe location (build).
  --skip-installer     Build signed ZIP/manifest only (build).
  -h, --help          Show this help.

Existing keys and output directories are never overwritten.
HELP
}

if [[ $# -eq 0 || ${1:-} == -h || ${1:-} == --help ]]; then usage; exit 0; fi
kmao_action=$1
shift
case "$kmao_action" in doctor|test|keygen|build|export) ;; *) usage >&2; exit 2 ;; esac

for kmao_tool in powershell.exe wslpath; do
    if ! command -v "$kmao_tool" >/dev/null 2>&1; then
        printf 'Missing %s. Run this command in WSL with Windows interoperability enabled.\n' "$kmao_tool" >&2
        exit 1
    fi
done
kmao_script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
kmao_repo_dir=$(cd -- "$kmao_script_dir/.." && pwd -P)
kmao_arguments=(-NoLogo -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$kmao_script_dir/Invoke-KmaoFromWsl.ps1")" -Action "$kmao_action" -RepositoryPath "$(wslpath -w "$kmao_repo_dir")")

while [[ $# -gt 0 ]]; do
    case "$1" in
        --private-key|--public-key|--output|--iscc)
            kmao_option=$1
            if [[ $# -lt 2 || -z $2 || $2 == --* ]]; then printf 'Missing path for %s\n' "$1" >&2; exit 2; fi
            case "$kmao_option" in
                --private-key) kmao_parameter=-PrivateKeyPath ;;
                --public-key) kmao_parameter=-PublicKeyPath ;;
                --output) kmao_parameter=-OutputDirectory ;;
                --iscc) kmao_parameter=-IsccPath ;;
            esac
            case "$kmao_action:$kmao_option" in
                keygen:--private-key|keygen:--public-key|build:*|export:--output) ;;
                *) printf 'Option %s is not valid for %s\n' "$kmao_option" "$kmao_action" >&2; exit 2 ;;
            esac
            kmao_path=$2
            if [[ $kmao_path != /* ]]; then kmao_path="$PWD/$kmao_path"; fi
            kmao_arguments+=("$kmao_parameter" "$(wslpath -w "$kmao_path")")
            shift 2
            ;;
        --skip-installer)
            if [[ $kmao_action != build ]]; then printf '%s\n' '--skip-installer requires build.' >&2; exit 2; fi
            kmao_arguments+=(-SkipInstaller)
            shift
            ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
done
exec powershell.exe "${kmao_arguments[@]}"
