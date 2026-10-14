# default apps

export TERM="xterm-256color"
export LC_ALL=uk_UA.UTF-8

# export EDITOR="helix"
# export VISUAL="helix"
# export SUDO_EDITOR="helix"
export EDITOR="nvim"
export VISUAL="nvim"
export SUDO_EDITOR="nvim"

# export TERMINAL="wezterm"
export TERMINAL="kitty"
# export TERMINAL="konsole"
# export TERMINAL="alacritty"

export BROWSER="google-chrome-stable"

# path
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:$HOME/.local/bin/:$PATH"
# Added by LM Studio CLI (lms)
export PATH="$PATH:/home/roman/.lmstudio/bin"

## Config programs
# starship
export STARSHIP_CONFIG="$HOME/.config/starship/starship.toml"

# home folder
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
