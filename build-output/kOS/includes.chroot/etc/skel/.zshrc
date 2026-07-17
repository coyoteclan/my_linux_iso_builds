
zstyle ':completion:*' completer _expand _complete _ignored _approximate
zstyle ':completion:*' expand prefix suffix
zstyle :compinstall filename '$HOME/.zshrc'

autoload -Uz compinit
compinit

HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000

bindkey -e

fpath=(/etc/xdg/zsh $fpath)
autoload -Uz prompt_setup && prompt_setup

setopt MENU_COMPLETE        # Automatically highlight first element of completion menu
setopt AUTO_LIST            # Automatically list choices on ambiguous completion.
setopt HIST_IGNORE_DUPS     # don't save duplicate commands
setopt HIST_IGNORE_SPACE    # don't save commands starting with space

source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Title
preexec() {
  print -Pn "\e]0;$1\a"
}
precmd() {
  print -Pn "\e]0;%~\a"
}

termom
