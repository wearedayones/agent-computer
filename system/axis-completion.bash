#!/bin/bash
# bash completion for axis
# Source this or install to /etc/bash_completion.d/axis

_axis_complete() {
  local cur prev words
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  # Top-level commands
  local top_cmds="boot check map update note task plan memory budget snapshot secret agent mcp cron cfg watch run log msg export help version status doctor ps size clean start stop restart diff alert ports sync peers fleet history trace env ctx metric skill sched dash plug"

  # Subcommands per command
  local note_sub="list read clear"
  local task_sub="add list done del assign priority clear"
  local plan_sub="set add done show clear"
  local memory_sub="set get list del"
  local budget_sub="log show threshold forecast reset"
  local snapshot_sub="list restore"
  local secret_sub="list get set rotate audit del"
  local agent_sub="list add show ping del"
  local mcp_sub="list add del show status"
  local cron_sub="list add del show"
  local cfg_sub="list get set del show edit"
  local watch_sub="list"
  local log_sub="today week errors all live summary search app"
  local run_sub="list"
  local msg_sub="list"
  local export_sub="--include-secrets"
  local trace_sub="log last search stats show"
  local env_sub="show set get del check list"
  local ctx_sub="brief save load list del"
  local metric_sub="list show trend top"
  local skill_sub="list add show search del"
  local sched_sub="add list log pause resume run del"
  local dash_sub="start stop status url tunnel"
  local plug_sub="list install uninstall new info"
  local sync_sub="peer push pull diff"
  local sync_peer_sub="add list ping del"
  local fleet_sub="list status run alert push"

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
    trace)    COMPREPLY=( $(compgen -W "$trace_sub" -- "$cur") ) ;;
    env)      COMPREPLY=( $(compgen -W "$env_sub" -- "$cur") ) ;;
    ctx)      COMPREPLY=( $(compgen -W "$ctx_sub" -- "$cur") ) ;;
    metric)   COMPREPLY=( $(compgen -W "$metric_sub" -- "$cur") ) ;;
    skill)    COMPREPLY=( $(compgen -W "$skill_sub" -- "$cur") ) ;;
    sched)    COMPREPLY=( $(compgen -W "$sched_sub" -- "$cur") ) ;;
    dash)     COMPREPLY=( $(compgen -W "$dash_sub" -- "$cur") ) ;;
    plug)     COMPREPLY=( $(compgen -W "$plug_sub" -- "$cur") ) ;;
    peers)    COMPREPLY=( $(compgen -W "$sync_sub" -- "$cur") ) ;;
    fleet)    COMPREPLY=( $(compgen -W "$fleet_sub" -- "$cur") ) ;;
    peer)     COMPREPLY=( $(compgen -W "$sync_peer_sub" -- "$cur") ) ;;
  esac
}

complete -F _axis_complete axis
# Also complete standalone commands
complete -F _axis_complete trace
complete -F _axis_complete ctx
complete -F _axis_complete metric
