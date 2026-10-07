#!/usr/bin/env bash

# ============================================================
# МОДУЛЬ: MODULE_NAME
# ============================================================
#
# V1.6:
# - пакети описуються в config/packages.conf;
# - metadata — в config/modules.conf;
# - конфіги разом із MODULE задаються в config/configs.conf;
# - MODULE_CONFIGS генерується автоматично;
# - модуль не звертається напряму до *_PACKAGES;
# - стандартна логіка виконується install_registered_module().
# ============================================================

# Необов'язковий post-install hook.
# Його ім'я потрібно вказати в MODULE_POST_HOOKS[MODULE_ID].
# configure_module() {
#     log_step "Додаткове налаштування MODULE_NAME."
#     run_cmd some-command --example
# }

install_module() {
    install_registered_module MODULE_ID
}
