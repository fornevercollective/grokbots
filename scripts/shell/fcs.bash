# grokbots · bash hook for fcs preserve
# Source:  source /Volumes/qbitOS/00.dev/grokbotsGH/scripts/shell/fcs.bash

if [[ -d "$HOME/.local/bin" ]]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
  esac
fi

_GROKBOTS_FCS="/Volumes/qbitOS/00.dev/grokbotsGH/scripts/fcs"

_fcs_bin() {
  if [[ -x "$_GROKBOTS_FCS" ]]; then
    bash "$_GROKBOTS_FCS" "$@"
    return $?
  fi
  if command -v fcs >/dev/null 2>&1; then
    command fcs "$@"
    return $?
  fi
  echo "fcs not found — run: bash /Volumes/qbitOS/00.dev/grokbotsGH/scripts/fcs --help" >&2
  return 127
}

if ! command -v fcs >/dev/null 2>&1; then
  fcs() { _fcs_bin "$@"; }
fi

if [[ $- == *i* ]]; then
  alias fc-preserve='fcs preserve'
  alias fc-etcher='fcs preserve'
fi
