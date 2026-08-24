# grokbots · zsh hook for fcs preserve
# Source:  source /Volumes/qbitOS/00.dev/grokbotsGH/scripts/shell/fcs.zsh

if [[ -d "$HOME/.local/bin" ]]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) path=("$HOME/.local/bin" $path) ;;
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
  print -u2 "fcs not found — run: bash /Volumes/qbitOS/00.dev/grokbotsGH/scripts/fcs --help"
  return 127
}

if ! command -v fcs >/dev/null 2>&1; then
  fcs() { _fcs_bin "$@"; }
fi
