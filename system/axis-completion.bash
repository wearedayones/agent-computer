#!/bin/bash
# bash completion for axis
# Source this or install to /etc/bash_completion.d/axis

_axis_complete() {
  local cur prev words
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  # Top-level commands
  local top_cmds="boot check map update note task plan memory budget snapshot secret agent mcp cron cfg watch run log msg export help version status"

  # Subcommands per command
  local note_sub="list read clear"
  local task_sub="add list done del clear"
  local plan_sub="set add done show clear"
  local memory_sub="set get list del"
  local budget_sub="log show reset"
  local snapshot_sub="list restore"
  local secret_sub="list get set del"
  local agent_sub="list add show ping del"
  local mcp_sub="list add del show status"
  local cron_sub="list add del show"
  local cfg_sub="list get set del show edit"
  local watch_sub="list"
  local log_sub="today week errors all"
  local run_sub="list"
  local msg_sub="list"
  local export_sub="--include-secrets"

  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "$top_cmds" -- "$cur") )
    return
  fi

  case "$prev" in
    note)     COMPREPLY=( $(compgen -W "$note_sub" -- "$cur") ) ;;
    task)     COMPREPLY=( $(compgen -W "$task_sub" -- "$cur") ) ;;
    plan)     COMPREPLY=( $(compgen -W "$plan_sub" -- "$cur") ) ;;
    memory)   COMPREPLY=( $(compgen -W "$memory_sub" -- "$cur") ) ;;
    budget)   COMPREPLY=( $(compgen -W "$budget_sub" -- "$cur") ) ;;
    snapshot) COMPREPLY=( $(compgen -W "$snapshot_sub" -- "$cur") ) ;;
    secret)   COMPREPLY=( $(compgen -W "$secret_sub" -- "$cur") ) ;;
    agent)    COMPREPLY=( $(compgen -W "$agent_sub" -- "$cur") ) ;;
    mcp)      COMPREPLY=( $(compgen -W "$mcp_sub" -- "$cur") ) ;;
    cron)     COMPREPLY=( $(compgen -W "$cron_sub" -- "$cur") ) ;;
    cfg)      COMPREPLY=( $(compgen -W "$cfg_sub" -- "$cur") ) ;;
    watch|run) COMPREPLY=( $(compgen -W "$(ls "$HOME/apps/" 2>/dev/null) list" -- "$cur") ) ;;
    log)      COMPREPLY=( $(compgen -W "$log_sub" -- "$cur") ) ;;
    msg)      COMPREPLY=( $(compgen -W "$msg_sub $(python3 -c "import json; d=json.load(open('$HOME/system/agents.json')); print(' '.join(d.get('agents',{}).keys()))" 2>/dev/null)" -- "$cur") ) ;;
    export)   COMPREPLY=( $(compgen -W "$export_sub" -- "$cur") ) ;;
  esac
}

complete -F _axis_complete axis
