# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi
unset rc

export PATH=$PATH:/home/leeparky04/.spicetify

# iNiR launcher PATH
case ":$PATH:" in
  *:"/home/leeparky04/.local/bin":*) ;;
  *) export PATH="/home/leeparky04/.local/bin:$PATH" ;;
esac
# end iNiR launcher PATH


# iNiR environment
export INIR_VENV="/home/leeparky04/.local/state/quickshell/.venv"
export ILLOGICAL_IMPULSE_VIRTUAL_ENV="$INIR_VENV"
# Apply terminal color sequences (Material You from wallpaper)
if [ -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt ]; then
  cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
fi
# end iNiR
