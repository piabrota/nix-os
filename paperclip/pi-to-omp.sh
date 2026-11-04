#!/usr/bin/env bash
# paperclip-pi: Paperclip's pi_local adapter calls `pi` (PAPERCLIP_PI_COMMAND). This shim turns that
# call into a call of the box's `omp` wrapper (omp/wrapper.nix). docs/PAPERCLIP.md says why.
#   --list-models          a fixed list: the two models of hermes/omp.yml (omp has no such flag)
#   --provider P --model M becomes --model P/M
#   --tools L              keeps the tools that omp has here: read, bash, edit, write, grep
#   --session F            becomes --no-session (omp resumes F, and fails when F does not exist)
#   --skill D              dropped; each folder of D is linked into $PI_CODING_AGENT_DIR/skills
# The last argument is the prompt. It is never read as a flag. Other arguments pass unchanged.
set -euo pipefail

if [ "$#" -eq 1 ] && [ "$1" = "--list-models" ]; then
  printf '%s\n' 'provider  model' 'anthropic  claude-sonnet-5-5' 'anthropic  claude-haiku-4-5'
  exit 0
fi

die() {
  echo "paperclip-pi: $*" >&2
  exit 2
}

link_skills() {
  local dir=${PI_CODING_AGENT_DIR:-} src s target
  [ -n "$dir" ] || return 0
  for src in "${skills[@]}"; do
    [ -d "$src" ] || continue
    mkdir -p "$dir/skills" || { echo "paperclip-pi: cannot make $dir/skills" >&2; return 0; }
    for s in "$src"/*/; do
      [ -d "$s" ] || continue
      s=${s%/}
      target=$dir/skills/${s##*/}
      [ "$s" -ef "$target" ] && continue
      if [ -e "$target" ] && [ ! -L "$target" ]; then
        echo "paperclip-pi: skill ${s##*/} exists, not linked" >&2
        continue
      fi
      ln -sfn "$s" "$target" || echo "paperclip-pi: cannot link skill ${s##*/}" >&2
    done
  done
}

has_last=0 last=''
if [ "$#" -gt 0 ]; then
  has_last=1
  last=${!#}
  set -- "${@:1:$#-1}"
fi

out=() skills=()
provider='' model='' tools='' model_at=-1 tools_at=-1 no_session=0
while [ "$#" -gt 0 ]; do
  case $1 in
    --provider | --model | --tools | --session | --skill | --mode | --thinking | --append-system-prompt)
      [ "$#" -ge 2 ] || die "$1 needs a value"
      flag=$1 value=$2
      shift 2
      ;;
    *)
      out+=("$1")
      shift
      continue
      ;;
  esac
  case $flag in
    --provider) provider=$value ;;
    --model)
      [ "$model_at" -ge 0 ] || { model_at=${#out[@]}; out+=(--model ''); }
      model=$value
      ;;
    --tools)
      [ "$tools_at" -ge 0 ] || { tools_at=${#out[@]}; out+=(--tools ''); }
      tools=$value
      ;;
    --session) no_session=1 ;;
    --skill) skills+=("$value") ;;
    *) out+=("$flag" "$value") ;;
  esac
done

if [ "$model_at" -ge 0 ]; then
  case $model in
    */*) ;;
    *) [ -z "$provider" ] || model=$provider/$model ;;
  esac
  out[model_at + 1]=$model
elif [ -n "$provider" ]; then
  out+=(--provider "$provider")
fi

if [ "$tools_at" -ge 0 ]; then
  list=''
  IFS=, read -r -a wanted <<<"$tools"
  for t in "${wanted[@]}"; do
    case $t in
      read | bash | edit | write | grep) ;;
      *) continue ;;
    esac
    case ",$list," in
      *",$t,"*) continue ;;
    esac
    list=${list:+$list,}$t
  done
  out[tools_at + 1]=${list:-read}
fi

[ "$no_session" -eq 0 ] || out+=(--no-session)
link_skills
[ "$has_last" -eq 0 ] || out+=("$last")
exec omp "${out[@]}"
