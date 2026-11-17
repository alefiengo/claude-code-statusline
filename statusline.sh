#!/usr/bin/env bash
# Two-line status line for Claude Code.
# To add a segment: write a function seg_<name> that prints its text
# (or nothing when it does not apply) and add it to LINE1 or LINE2 at the end of the file.

input=$(cat)

cwd='' model='' effort='' lines_added=0 lines_removed=0 ctx='' h5='' h5_reset='' d7='' d7_reset=''
session='' duration_ms='' cache_warm='' cache_expires=''
spend='' spend_reset='' spend_used='' spend_limit=''

# Percentages and dollar amounts are rounded here, in jq, so the shell only handles integers and the
# result does not depend on the locale's decimal separator.
eval "$(jq -r '
  def int: if . == null then "" else (. + 0.5 | floor) end;
  @sh "cwd=\(.workspace.current_dir // .cwd // "")",
  @sh "session=\(.session_name // "" | if length > 30 then .[:29] + "…" else . end)",
  @sh "duration_ms=\(.cost.total_duration_ms // "")",
  @sh "cache_warm=\(if .prompt_cache.warm == null then "" else (.prompt_cache.warm | tostring) end)",
  @sh "cache_expires=\(.prompt_cache.expires_at // "")",
  @sh "model=\(.model.display_name // "")",
  @sh "effort=\(.effort.level // "")",
  @sh "lines_added=\(.cost.total_lines_added // 0)",
  @sh "lines_removed=\(.cost.total_lines_removed // 0)",
  @sh "ctx=\(.context_window.used_percentage | int)",
  @sh "h5=\(.rate_limits.five_hour.used_percentage | int)",
  @sh "h5_reset=\(.rate_limits.five_hour.resets_at // "")",
  @sh "d7=\(.rate_limits.seven_day.used_percentage | int)",
  @sh "d7_reset=\(.rate_limits.seven_day.resets_at // "")",
  @sh "spend=\(.rate_limits.spend_limit.used_percentage | int)",
  @sh "spend_reset=\(.rate_limits.spend_limit.resets_at // "")",
  @sh "spend_used=\(.rate_limits.spend_limit.used_usd | int)",
  @sh "spend_limit=\(.rate_limits.spend_limit.limit_usd | int)"
' <<<"$input" 2>/dev/null)"

GIT=$(command -v git || echo /usr/bin/git)
git_cmd() { "$GIT" --no-optional-locks -C "$cwd" "$@" 2>/dev/null; }

fmt_time() {
  local ts=${1%.*}
  # LC_ALL=C keeps month names in English whatever the user's locale.
  LC_ALL=C date -d "@$ts" "+$2" 2>/dev/null || LC_ALL=C date -r "$ts" "+$2" 2>/dev/null
}

# Palette
C_DIR='1;34'
C_GIT='1;33'
C_ADDED='38;5;114'
C_REMOVED='38;5;174'
C_LABEL='2'
C_SYNC='38;5;117'
C_SESSION='2;3'

paint() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
SEP=" $(paint 2 '│') "

model_color() {
  case "$1" in
    *Opus*) echo '1;38;5;141' ;;
    *Sonnet*) echo '1;38;5;75' ;;
    *Haiku*) echo '1;38;5;80' ;;
    *Fable*) echo '1;38;5;215' ;;
    *) echo '1;36' ;;
  esac
}

effort_color() {
  case "$1" in
    low) echo '38;5;245' ;;
    medium) echo '38;5;222' ;;
    high) echo '38;5;208' ;;
    xhigh) echo '38;5;202' ;;
    max) echo '38;5;196' ;;
    *) echo '37' ;;
  esac
}

level_color() {
  local v
  v=$1
  if ((v >= 80)); then echo '1;31'
  elif ((v >= 50)); then echo '1;33'
  else echo '1;32'
  fi
}

bar() {
  local v half full i out='' rest='' color
  v=$1
  half=$(((v * 2 + 5) / 10))
  ((half > 20)) && half=20
  full=$((half / 2))
  for ((i = 0; i < full; i++)); do out+='━'; done
  ((half % 2)) && { out+='╸'; ((i++)); }
  for (( ; i < 10; i++)); do rest+='─'; done
  color=$(level_color "$v")
  printf '%s%s %s' "$(paint "$color" "$out")" "$(paint 2 "$rest")" "$(paint "$color" "$v%")"
}

# Line 1 segments
seg_dir() { [ -n "$cwd" ] && paint "$C_DIR" "${cwd##*/}"; }

seg_git() {
  local branch dirty='' parts=() behind ahead
  [ -n "$cwd" ] && branch=$(git_cmd branch --show-current)
  if [ -n "$branch" ]; then
    [ -n "$(git_cmd status --porcelain | head -1)" ] && dirty='*'
    parts+=("$(paint "$C_GIT" "$branch$dirty")")
    read -r behind ahead < <(git_cmd rev-list --left-right --count '@{upstream}...HEAD')
    ((ahead > 0)) && parts+=("$(paint "$C_SYNC" "↑$ahead")")
    ((behind > 0)) && parts+=("$(paint "$C_SYNC" "↓$behind")")
  fi
  [ -n "$(seg_diff)" ] && parts+=("$(seg_diff)")
  printf '%s' "${parts[*]}"
}

seg_session() { [ -n "$session" ] && paint "$C_SESSION" "$session"; }

seg_duration() {
  [ -z "$duration_ms" ] && return
  local min=$((${duration_ms%.*} / 60000))
  if ((min >= 60)); then
    paint "$C_LABEL" "◷ $((min / 60))h$(printf '%02d' $((min % 60)))m"
  else
    paint "$C_LABEL" "◷ ${min}m"
  fi
}

seg_cache() {
  [ -z "$cache_warm" ] && return
  local left
  if [ "$cache_warm" = true ] && [ -n "$cache_expires" ]; then
    left=$(((${cache_expires%.*} - $(date +%s)) / 60))
    if ((left <= 0)); then paint '38;5;245' 'cache cold'
    elif ((left <= 10)); then paint '1;33' "cache ${left}m"
    else paint '1;32' "cache ${left}m"
    fi
  else
    paint '38;5;245' 'cache cold'
  fi
}

seg_model() {
  [ -z "$model" ] && return
  local mc
  mc=$(model_color "$model")
  paint "$mc" "$model"
  [ -n "$effort" ] && printf ' %s' "$(paint "$(effort_color "$effort")" "$effort")"
}

seg_diff() {
  [ "$lines_added" = 0 ] && [ "$lines_removed" = 0 ] && return
  printf '%s %s' "$(paint "$C_ADDED" "+$lines_added")" "$(paint "$C_REMOVED" "-$lines_removed")"
}

# Line 2 segments
seg_ctx() { [ -n "$ctx" ] && printf '%s %s' "$(paint "$C_LABEL" ctx)" "$(bar "$ctx")"; }

seg_5h() {
  [ -z "$h5" ] && return
  printf '%s %s' "$(paint "$C_LABEL" 5h)" "$(bar "$h5")"
  [ -n "$h5_reset" ] && printf ' %s' "$(paint "$C_LABEL" "↻ $(fmt_time "$h5_reset" %H:%M)")"
}

seg_7d() {
  [ -z "$d7" ] && return
  printf '%s %s' "$(paint "$C_LABEL" 7d)" "$(bar "$d7")"
  [ -n "$d7_reset" ] && printf ' %s' "$(paint "$C_LABEL" "↻ $(fmt_time "$d7_reset" '%b %d %H:%M')")"
}

# Spend limit, only behind a Claude apps gateway that sets one.
seg_spend() {
  [ -z "$spend" ] && return
  printf '%s %s' "$(paint "$C_LABEL" spend)" "$(bar "$spend")"
  [ -n "$spend_used" ] && [ -n "$spend_limit" ] && printf ' %s' "$(paint "$C_LABEL" "\$$spend_used/\$$spend_limit")"
  [ -n "$spend_reset" ] && printf ' %s' "$(paint "$C_LABEL" "↻ $(fmt_time "$spend_reset" '%b %d %H:%M')")"
}

render() {
  local out='' s f
  for f in "$@"; do
    s=$("$f")
    [ -n "$s" ] && out+="${out:+$SEP}$s"
  done
  printf '%s' "$out"
}

LINE1=(seg_dir seg_session seg_git seg_model seg_cache seg_duration)
LINE2=(seg_ctx seg_5h seg_7d seg_spend)

render "${LINE1[@]}"
line2=$(render "${LINE2[@]}")
[ -n "$line2" ] && printf '\n%s' "$line2"
exit 0
