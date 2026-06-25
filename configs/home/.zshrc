
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
