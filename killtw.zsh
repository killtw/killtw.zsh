#Color Shortcuts
R=$fg[red]
G=$fg[green]
B=$fg[blue]
Y=$fg[yellow]
CYAN=$fg[cyan]
RESET=$reset_color

PROMPT_HOST="[%{$B%}%n%{$Y%}@%{$R%}%m%{$RESET%}] "
PROMPT_DIR="%{$CYAN%}%1~%{$RESET%} "
GIT_PROMPT_PREFIX="%{$B%}<%{$R%}"
GIT_PROMPT_SUFFIX="%{$B%}>%{$RESET%} "
GIT_PROMPT_DIRTY="%{$R%}%B✘"
GIT_PROMPT_CLEAN="%{$G%}✔"

prompt_setup() {
    autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
    autoload -Uz async && async

    add-zsh-hook precmd prompt_precmd

    zle -N prompt_reset_prompt
}

prompt_precmd() {
    prompt_async_tasks

    prompt_render
}

prompt_async_renice() {
    setopt localoptions noshwordsplit

    if command -v renice >/dev/null; then
        command renice +15 -p $$
	fi

    if command -v ionice >/dev/null; then
        command ionice -c 3 -p $$
    fi
}

prompt_async_tasks() {
    (( !${async_worker_started:-0} )) && {
		async_start_worker "killtw.zsh" -u -n
		async_register_callback "killtw.zsh" prompt_async_callback
		typeset -g async_worker_started=1
        async_job "killtw.zsh" prompt_async_renice
	}

    async_worker_eval "killtw.zsh" builtin cd -q $PWD

    typeset -gA global_git_info

    if [[ -n $global_git_info[branch] ]]; then
        if [[ $PWD != ${global_git_info[pwd]}* ]]; then
            async_flush_jobs "killtw.zsh"

            unset git_dirty
            global_git_info[branch]=
            global_git_info[top]=
        fi
    fi

    async_job "killtw.zsh" prompt_async_vcs_info $?

    [[ -n $global_git_info[top] ]] || return

    prompt_async_refresh
}

prompt_async_refresh() {
    async_job "killtw.zsh" prompt_async_git_dirty
}

prompt_async_vcs_info() {
    setopt localoptions noshwordsplit

    zstyle ':vcs_info:*' enable git
    zstyle ':vcs_info:*' use-simple true
    zstyle ':vcs_info:*' max-exports 2

    zstyle ':vcs_info:git*' formats '%b' '%R'
	zstyle ':vcs_info:git*' actionformats '%b' '%R'

    vcs_info

    local -A info
	info[pwd]=$PWD
	info[branch]=$vcs_info_msg_0_
    info[top]=$vcs_info_msg_1_

	print -r - ${(@kvq)info}
}

prompt_async_git_dirty() {
    setopt localoptions noshwordsplit
	test -z "$(command git status --porcelain --ignore-submodules --untracked-files=normal)"

    return $?
}

prompt_async_callback() {
    setopt localoptions noshwordsplit
    local job=$1 code=$2 outout=$3 pendings=$6
    local should_render=0

    case $job in
        \[async])
            if [[ $code -eq 2 ]]; then
                typeset -g async_worker_started=0
            fi
            ;;
        prompt_async_vcs_info)
            local -A info
            typeset -gA global_git_info
            info=${(@Q)${(z)outout}}
            if [[ $info[pwd] != $PWD ]]; then
                return
            fi
            if [[ $info[top] = $global_git_info[top] ]]; then
                if [[ $global_git_info[pwd] = ${PWD}* ]]; then
                    global_git_info[pwd]=$PWD
                fi
            else
                global_git_info[pwd]=$PWD
            fi

            [[ -n $info[top] ]] && [[ -z $global_git_info[top] ]] && prompt_async_refresh

            global_git_info[branch]=$info[branch]
            global_git_info[top]=$info[top]

            should_render=1
        ;;
        prompt_async_git_dirty)
            local dirty=$git_dirty
            typeset -g git_dirty=$code

            [[ $dirty != $git_dirty ]] && should_render=1
        ;;
        prompt_async_renice)
        ;;
    esac

    if (( pendings )); then
        (( should_render )) && typeset -g async_render=1
        return
    fi

    [[ ${async_render:-$should_render} = 1 ]] && prompt_render
    unset async_render
}

prompt_render() {
    setopt localoptions noshwordsplit

    local -a git_status

    if [[ -n $global_git_info[branch] ]]; then
        git_status+='${GIT_PROMPT_PREFIX}% '
        git_status+=$global_git_info[branch]

        if (( git_dirty )); then
            git_status+='${GIT_PROMPT_DIRTY}% '
        else
            git_status+='${GIT_PROMPT_CLEAN}% '
        fi
        git_status+='${GIT_PROMPT_SUFFIX}% '
    fi

    local -ah parts
    parts=(
        '${PROMPT_HOST}% '
        '${PROMPT_DIR}% '
        "${(j..)git_status}"
        '%% %b%{$RESET%}'
    )

    PROMPT="${(j..)parts}"
    # PROMPT='${PROMPT_HOST}% ${PROMPT_DIR}% ${vcs_info_msg_0_}%% %b%{$RESET%}'
    RPROMPT='[%{$G%}%T%f]%{$RESET%}'

    local expanded_prompt
	expanded_prompt="${(S%%)PROMPT}"
    if [[ $prompt_last_prompt != $expanded_prompt ]]; then
		prompt_reset_prompt
	fi

	typeset -g prompt_last_prompt=$expanded_prompt
}

prompt_reset_prompt() {
    zle && zle .reset-prompt
}

prompt_setup "$@"
