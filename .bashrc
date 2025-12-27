#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# i3 Window Property Watcher
i3prop() {
  watch -t -n 0.1 "i3-msg -t get_tree | jq '.. | select(.focused? == true) | {class: .window_properties.class, title: .name, instance: .window_properties.instance, role: .window_properties.window_role, window_type: .window_type, window_rect: .window_rect}'"
}

alias ls='ls --color=auto'
alias grep='grep --color=auto'

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi
unset rc

# PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
PS1='\[\e[1;34m\]\w \[\e[1;32m\]$ \[\e[0m\]'

export PATH="$HOME/.bun/bin:$PATH"

# cleaning up duplicate PATH
clean_path() {
  echo "$PATH" | tr -s ':' '\n' | awk '!seen[$0]++' | tr '\n' ':' | sed 's/:$//'
}

export PATH=$(clean_path)
unset clean_path

# Set up fzf key bindings and fuzzy completion
eval "$(fzf --bash)"
