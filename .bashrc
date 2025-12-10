#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '

# cleaning up duplicate PATH
clean_path() {
  echo "$PATH" | tr -s ':' '\n' | awk '!seen[$0]++' | tr '\n' ':' | sed 's/:$//'
}

export PATH=$(clean_path)
unset clean_path
