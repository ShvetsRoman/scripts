# Powerlevel10k — Nordic v1.0
# ------------------------------------------------------------
# Компактна Nordic-тема для Zsh / Powerlevel10k.
#
# Стиль:
#   • 2 рядки
#   • прозорий фон
#   • мінімум сегментів
#   • Nord / Polar Night + Frost + Aurora
#   • Git зі стислим статусом
#   • Python virtualenv
#   • Rust / Kubernetes / Terraform за потреби
#   • успіх: ➜   помилка: ✘
#
# Застосування без перезапуску Zsh:
#   source ~/.p10k_my.zsh
# ------------------------------------------------------------

'builtin' 'local' '-a' 'p10k_config_opts'
[[ ! -o 'aliases' ]] || p10k_config_opts+=('aliases')
[[ ! -o 'sh_glob' ]] || p10k_config_opts+=('sh_glob')
[[ ! -o 'no_brace_expand' ]] || p10k_config_opts+=('no_brace_expand')
'builtin' 'setopt' 'no_aliases' 'no_sh_glob' 'brace_expand'

() {
    emulate -L zsh -o extended_glob

    # Дозволяє перезавантажувати конфігурацію через `source`.
    unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'

    [[ $ZSH_VERSION == (5.<1->*|<6->.*) ]] || return

    # ============================================================
    # Nordic palette
    # ============================================================

    # Polar Night.
    typeset -g NORD_POLAR_0='#2E3440'
    typeset -g NORD_POLAR_1='#3B4252'
    typeset -g NORD_POLAR_2='#434C5E'
    typeset -g NORD_POLAR_3='#4C566A'

    # Snow Storm.
    typeset -g NORD_SNOW_0='#D8DEE9'
    typeset -g NORD_SNOW_1='#E5E9F0'
    typeset -g NORD_SNOW_2='#ECEFF4'

    # Frost.
    typeset -g NORD_FROST_0='#8FBCBB'
    typeset -g NORD_FROST_1='#88C0D0'
    typeset -g NORD_FROST_2='#81A1C1'
    typeset -g NORD_FROST_3='#5E81AC'

    # Aurora.
    typeset -g NORD_RED='#BF616A'
    typeset -g NORD_ORANGE='#D08770'
    typeset -g NORD_YELLOW='#EBCB8B'
    typeset -g NORD_GREEN='#A3BE8C'
    typeset -g NORD_PURPLE='#B48EAD'

    # ============================================================
    # Prompt layout
    # ============================================================

    typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
        os_icon
        dir
        vcs
        newline
        prompt_char
    )

    typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
        # =========================[ Line #1 ]=========================
        status                 # exit code of the last command
        command_execution_time # duration of the last command
        background_jobs        # presence of background jobs
        direnv                 # direnv status (https://direnv.net/)
        asdf                   # asdf version manager (https://github.com/asdf-vm/asdf)
        docker_compose
        python_venv
        pyenv    # python environment (https://github.com/pyenv/pyenv)
        anaconda # conda environment (https://conda.io/)
        goenv    # go environment (https://github.com/syndbg/goenv)
        nodenv   # node.js version from nodenv (https://github.com/nodenv/nodenv)
        nvm      # node.js version from nvm (https://github.com/nvm-sh/nvm)
        nodeenv  # node.js environment (https://github.com/ekalinin/nodeenv)
        # node_version          # node.js version
        # go_version            # go version (https://golang.org)
        rust_version # rustc version (https://www.rust-lang.org)
        # dotnet_version        # .NET version (https://dotnet.microsoft.com)
        # php_version           # php version (https://www.php.net/)
        # laravel_version       # laravel php framework version (https://laravel.com/)
        # java_version          # java version (https://www.java.com/)
        # package               # name@version from package.json (https://docs.npmjs.com/files/package.json)
        rbenv         # ruby version from rbenv (https://github.com/rbenv/rbenv)
        rvm           # ruby version from rvm (https://rvm.io)
        fvm           # flutter version management (https://github.com/leoafarias/fvm)
        luaenv        # lua version from luaenv (https://github.com/cehoffman/luaenv)
        jenv          # java version from jenv (https://github.com/jenv/jenv)
        plenv         # perl version from plenv (https://github.com/tokuhirom/plenv)
        perlbrew      # perl version from perlbrew (https://github.com/gugod/App-perlbrew)
        phpenv        # php version from phpenv (https://github.com/phpenv/phpenv)
        scalaenv      # scala version from scalaenv (https://github.com/scalaenv/scalaenv)
        haskell_stack # haskell version from stack (https://haskellstack.org/)
        kubecontext   # current kubernetes context (https://kubernetes.io/)
        terraform     # terraform workspace (https://www.terraform.io)
        # terraform_version     # terraform version (https://www.terraform.io)
        aws                # aws profile (https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html)
        aws_eb_env         # aws elastic beanstalk environment (https://aws.amazon.com/elasticbeanstalk/)
        azure              # azure account name (https://docs.microsoft.com/en-us/cli/azure)
        gcloud             # google cloud cli account and project (https://cloud.google.com/)
        google_app_cred    # google application credentials (https://cloud.google.com/docs/authentication/production)
        toolbox            # toolbox name (https://github.com/containers/toolbox)
        context            # user@hostname
        nordvpn            # nordvpn connection status, linux only (https://nordvpn.com/)
        ranger             # ranger shell (https://github.com/ranger/ranger)
        yazi               # yazi shell (https://github.com/sxyazi/yazi)
        nnn                # nnn shell (https://github.com/jarun/nnn)
        lf                 # lf shell (https://github.com/gokcehan/lf)
        xplr               # xplr shell (https://github.com/sayanarijit/xplr)
        vim_shell          # vim shell indicator (:sh)
        midnight_commander # midnight commander shell (https://midnight-commander.org/)
        nix_shell          # nix shell (https://nixos.org/nixos/nix-pills/developing-with-nix-shell.html)
        chezmoi_shell      # chezmoi shell (https://www.chezmoi.io/)
        # vpn_ip                # virtual private network indicator
        # load                  # CPU load
        # disk_usage            # disk usage
        # ram                   # free RAM
        # swap                  # used swap
        todo                  # todo items (https://github.com/todotxt/todo.txt-cli)
        timewarrior           # timewarrior tracking status (https://timewarrior.net/)
        taskwarrior           # taskwarrior task count (https://taskwarrior.org/)
        per_directory_history # Oh My Zsh per-directory-history local/global indicator
        # cpu_arch              # CPU architecture
        # time                  # current time
        # =========================[ Line #2 ]=========================
        newline
        # ip                    # ip address and bandwidth usage for a specified network interface
        # public_ip             # public IP address
        # proxy                 # system-wide http/https/ftp proxy
        # battery               # internal battery
        # wifi                  # wifi speed
        # example               # example user-defined segment (see prompt_example function below)
    )

    # Nerd Font Complete потрібен для іконок.
    typeset -g POWERLEVEL9K_MODE=nerdfont-complete
    typeset -g POWERLEVEL9K_ICON_PADDING=none
    typeset -g POWERLEVEL9K_ICON_BEFORE_CONTENT=true

    # Прозорий фон і мінімальні розділювачі.
    typeset -g POWERLEVEL9K_BACKGROUND=
    typeset -g POWERLEVEL9K_{LEFT,RIGHT}_{LEFT,RIGHT}_WHITESPACE=
    typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SUBSEGMENT_SEPARATOR=' '
    typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SEGMENT_SEPARATOR=

    # Не додавати зайвий порожній рядок перед prompt.
    typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true

    # ============================================================
    # Multiline — чистий Nordic prompt без рамок
    # ============================================================

    typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX=
    typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_PREFIX=
    typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX=
    typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_SUFFIX=
    typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_SUFFIX=
    typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_SUFFIX=

    typeset -g POWERLEVEL9K_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=
    typeset -g POWERLEVEL9K_RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL=

    typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR=' '
    typeset -g POWERLEVEL9K_SHOW_RULER=false

    # ============================================================
    # OS icon
    # ============================================================

    typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND=$NORD_FROST_1
    # typeset -g POWERLEVEL9K_OS_ICON_VISUAL_IDENTIFIER_EXPANSION=''

    # ============================================================
    # Prompt character
    # ============================================================

    typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VIINS_FOREGROUND=$NORD_GREEN
    typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VIINS_FOREGROUND=$NORD_RED
    typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VICMD_FOREGROUND=$NORD_GREEN
    typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VICMD_FOREGROUND=$NORD_RED
    typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VIVIS_FOREGROUND=$NORD_GREEN
    typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VIVIS_FOREGROUND=$NORD_RED
    typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VIOWR_FOREGROUND=$NORD_GREEN
    typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VIOWR_FOREGROUND=$NORD_RED

    typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='➜'
    typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VICMD_CONTENT_EXPANSION='❮'
    typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIVIS_CONTENT_EXPANSION='V'
    typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIOWR_CONTENT_EXPANSION='▶'
    typeset -g POWERLEVEL9K_PROMPT_CHAR_OVERWRITE_STATE=true

    typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
    typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=

    # ============================================================
    # Directory
    # ============================================================

    typeset -g POWERLEVEL9K_DIR_FOREGROUND=$NORD_FROST_2
    typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=$NORD_FROST_3
    typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=$NORD_FROST_1
    typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=true

    # ~/projects/my-project замість надмірно довгого абсолютного шляху.
    typeset -g POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER=false
    typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=80
    typeset -g POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS=40
    typeset -g POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS_PCT=50
    typeset -g POWERLEVEL9K_DIR_HYPERLINK=false
    typeset -g POWERLEVEL9K_DIR_SHOW_WRITABLE=v3

    # ============================================================
    # context: user@hostname
    # ============================================================

    # Context color when running with privileges.
    typeset -g POWERLEVEL9K_CONTEXT_ROOT_FOREGROUND=178
    # Context color in SSH without privileges.
    typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_FOREGROUND=180
    # Default context color (no privileges, no SSH).
    typeset -g POWERLEVEL9K_CONTEXT_FOREGROUND=180

    # Context format when running with privileges: bold user@hostname.
    typeset -g POWERLEVEL9K_CONTEXT_ROOT_TEMPLATE='%B%n@%m'
    # Context format when in SSH without privileges: user@hostname.
    typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_TEMPLATE='%n@%m'
    # Default context format (no privileges, no SSH): user@hostname.
    typeset -g POWERLEVEL9K_CONTEXT_TEMPLATE='%n@%m'

    # Don't show context unless running with privileges or in SSH.
    # Tip: Remove the next line to always show context.
    typeset -g POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}_{CONTENT,VISUAL_IDENTIFIER}_EXPANSION=

    # Custom icon.
    # typeset -g POWERLEVEL9K_CONTEXT_VISUAL_IDENTIFIER_EXPANSION='⭐'
    # Custom prefix.
    # typeset -g POWERLEVEL9K_CONTEXT_PREFIX='%fwith '

    # ============================================================
    # Docker / Docker Compose
    # ============================================================

    function prompt_docker_compose() {
        emulate -L zsh

        local project_name=''

        # Показуємо сегмент лише в каталозі з Compose-файлом.
        if [[ -f docker-compose.yml ||
            -f docker-compose.yaml ||
            -f compose.yml ||
            -f compose.yaml ]]; then

            # COMPOSE_PROJECT_NAME має пріоритет.
            # Якщо його немає — використовуємо назву каталогу.
            project_name=${COMPOSE_PROJECT_NAME:-${PWD:t}}

            [[ -n $project_name ]] || return 0

            p10k segment \
                -i ' ' \
                -f "$NORD_FROST_1" \
                -t "${project_name//\%/%%}"
        fi
    }

    # ============================================================
    # Git
    # ============================================================

    typeset -g POWERLEVEL9K_VCS_BRANCH_ICON=' '
    typeset -g POWERLEVEL9K_VCS_UNTRACKED_ICON='?'
    typeset -g POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY=-1
    typeset -g POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN='~'
    typeset -g POWERLEVEL9K_VCS_DISABLE_GITSTATUS_FORMATTING=true
    typeset -g POWERLEVEL9K_VCS_BACKENDS=(git)
    typeset -g POWERLEVEL9K_VCS_{STAGED,UNSTAGED,UNTRACKED,CONFLICTED,COMMITS_AHEAD,COMMITS_BEHIND}_MAX_NUM=-1

    # Компактний Git formatter.
    #   main
    #   main ↑2
    #   main +1 !2 ?3
    #   main ~1 +2 !3 ?1
    function my_git_formatter() {
        emulate -L zsh

        if [[ -n $P9K_CONTENT ]]; then
            typeset -g my_git_format=$P9K_CONTENT
            return
        fi

        if (($1)); then
            local clean="%F{$NORD_GREEN}"
            local modified="%F{$NORD_YELLOW}"
            local untracked="%F{$NORD_FROST_1}"
            local conflicted="%F{$NORD_RED}"
            local meta="%F{$NORD_SNOW_0}"
        else
            local clean='%F{244}'
            local modified='%F{244}'
            local untracked='%F{244}'
            local conflicted='%F{244}'
            local meta='%F{244}'
        fi

        local res=''

        if [[ -n $VCS_STATUS_LOCAL_BRANCH ]]; then
            local branch=${(V)VCS_STATUS_LOCAL_BRANCH}
            (($#branch > 32)) && branch[13,-13]='…'
            res+="${clean}${(g::)POWERLEVEL9K_VCS_BRANCH_ICON}${branch//\%/%%}"
        elif [[ -n $VCS_STATUS_TAG ]]; then
            local tag=${(V)VCS_STATUS_TAG}
            (($#tag > 32)) && tag[13,-13]='…'
            res+="${meta}#${clean}${tag//\%/%%}"
        else
            res+="${meta}@${clean}${VCS_STATUS_COMMIT[1,8]}"
        fi

        # Віддалена гілка відображається лише коли вона відрізняється.
        if [[ -n ${VCS_STATUS_REMOTE_BRANCH:#$VCS_STATUS_LOCAL_BRANCH} ]]; then
            res+=" ${meta}:${clean}${(V)VCS_STATUS_REMOTE_BRANCH//\%/%%}"
        fi

        # Ahead / behind.
        ((VCS_STATUS_COMMITS_BEHIND)) && res+=" ${modified}⇣${VCS_STATUS_COMMITS_BEHIND}"
        ((VCS_STATUS_COMMITS_AHEAD)) && res+=" ${clean}⇡${VCS_STATUS_COMMITS_AHEAD}"

        # Stash / merge / conflict / staged / unstaged / untracked.
        ((VCS_STATUS_STASHES)) && res+=" ${meta}*${VCS_STATUS_STASHES}"
        [[ -n $VCS_STATUS_ACTION ]] && res+=" ${conflicted}${VCS_STATUS_ACTION}"
        ((VCS_STATUS_NUM_CONFLICTED)) && res+=" ${conflicted}~${VCS_STATUS_NUM_CONFLICTED}"
        ((VCS_STATUS_NUM_STAGED)) && res+=" ${modified}+${VCS_STATUS_NUM_STAGED}"
        ((VCS_STATUS_NUM_UNSTAGED)) && res+=" ${modified}!${VCS_STATUS_NUM_UNSTAGED}"
        ((VCS_STATUS_NUM_UNTRACKED)) && res+=" ${untracked}?${VCS_STATUS_NUM_UNTRACKED}"

        typeset -g my_git_format=$res
    }
    functions -M my_git_formatter 2>/dev/null

    typeset -g POWERLEVEL9K_VCS_CONTENT_EXPANSION='${$((my_git_formatter(1)))+${my_git_format}}'
    typeset -g POWERLEVEL9K_VCS_LOADING_CONTENT_EXPANSION='${$((my_git_formatter(0)))+${my_git_format}}'
    typeset -g POWERLEVEL9K_VCS_VISUAL_IDENTIFIER_COLOR=$NORD_FROST_1
    typeset -g POWERLEVEL9K_VCS_LOADING_VISUAL_IDENTIFIER_COLOR=$NORD_POLAR_3
    typeset -g POWERLEVEL9K_VCS_CLEAN_FOREGROUND=$NORD_GREEN
    typeset -g POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND=$NORD_FROST_1
    typeset -g POWERLEVEL9K_VCS_MODIFIED_FOREGROUND=$NORD_YELLOW

    # ============================================================
    # Python / virtualenv
    # ============================================================

    function prompt_python_venv() {
        emulate -L zsh

        local dir="$PWD"
        local project_root=''
        local venv_name=''
        local python_version=''
        local content=''

        # Шукаємо корінь Python-проєкту в поточному каталозі
        # та в усіх батьківських каталогах.
        while [[ "$dir" != "/" ]]; do
            if [[ -f "$dir/pyproject.toml" ||
                -f "$dir/requirements.txt" ||
                -f "$dir/requirements-dev.txt" ||
                -f "$dir/setup.py" ||
                -f "$dir/setup.cfg" ||
                -f "$dir/Pipfile" ||
                -f "$dir/poetry.lock" ||
                -f "$dir/uv.lock" ||
                -d "$dir/.venv" ||
                -d "$dir/.venv-"* ]]; then
                project_root="$dir"
                break
            fi

            dir="${dir:h}"
        done

        # Поточний каталог не належить до Python-проєкту.
        [[ -n $project_root ]] || return 0

        # Активне virtualenv.
        if [[ -n ${VIRTUAL_ENV:-} ]]; then
            venv_name=${VIRTUAL_ENV:t}
            content+="🐍(venv):${venv_name}"
        fi

        # Версія Python.
        if (($+commands[python])); then
            python_version=$(python --version 2>/dev/null)
            python_version=${python_version#Python }
        fi

        [[ -n $python_version ]] || return 0

        [[ -n $content ]] && content+='  '
        content+=" Python ${python_version}"

        p10k segment \
            -f "$NORD_PURPLE" \
            -t "${content//\%/%%}"
    }

    typeset -g POWERLEVEL9K_VIRTUALENV_FOREGROUND=$NORD_PURPLE
    typeset -g POWERLEVEL9K_VIRTUALENV_SHOW_PYTHON_VERSION=true
    typeset -g POWERLEVEL9K_VIRTUALENV_SHOW_WITH_PYENV=false
    typeset -g POWERLEVEL9K_VIRTUALENV_GENERIC_NAMES=()
    typeset -g POWERLEVEL9K_VIRTUALENV_VISUAL_IDENTIFIER_EXPANSION='🐍'
    typeset -g POWERLEVEL9K_VIRTUALENV_CONTENT_EXPANSION='(venv):${VIRTUAL_ENV:t}'

    # ============================================================
    # Rust
    # ============================================================

    typeset -g POWERLEVEL9K_RUST_VERSION_FOREGROUND=$NORD_ORANGE
    typeset -g POWERLEVEL9K_RUST_VERSION_VISUAL_IDENTIFIER_EXPANSION=' '

    # ============================================================
    # Kubernetes
    # ============================================================

    typeset -g POWERLEVEL9K_KUBECONTEXT_FOREGROUND=$NORD_FROST_0
    typeset -g POWERLEVEL9K_KUBECONTEXT_VISUAL_IDENTIFIER_EXPANSION='󱃾 '
    typeset -g POWERLEVEL9K_KUBECONTEXT_DEFAULT_CONTENT_EXPANSION='${P9K_CONTENT}'

    # ============================================================
    # Terraform
    # ============================================================

    typeset -g POWERLEVEL9K_TERRAFORM_FOREGROUND=$NORD_FROST_3
    typeset -g POWERLEVEL9K_TERRAFORM_VISUAL_IDENTIFIER_EXPANSION='󱁢 '

    # ============================================================
    # Command execution time
    # ============================================================

    typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
    typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=0
    typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=$NORD_SNOW_0
    typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FORMAT='d h m s'
    typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_VISUAL_IDENTIFIER_EXPANSION='󱎫 '

    # ============================================================
    # Background jobs
    # ============================================================

    typeset -g POWERLEVEL9K_BACKGROUND_JOBS_VERBOSE=false
    typeset -g POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND=$NORD_YELLOW
    typeset -g POWERLEVEL9K_BACKGROUND_JOBS_VISUAL_IDENTIFIER_EXPANSION='󰒋 '

    # ============================================================
    # General behavior
    # ============================================================

    # У старих командах prompt залишається повним.
    typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=off

    # Instant prompt зменшує час старту Zsh.
    typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

    # Hot reload вимкнений для кращої продуктивності.
    typeset -g POWERLEVEL9K_DISABLE_HOT_RELOAD=true

    # Якщо p10k уже завантажений — застосувати конфіг одразу.
    ((! $+functions[p10k])) || p10k reload
}

typeset -g POWERLEVEL9K_CONFIG_FILE=${${(%):-%x}:a}

((${#p10k_config_opts})) && setopt ${p10k_config_opts[@]}
'builtin' 'unset' 'p10k_config_opts'
