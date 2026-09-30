#!/usr/bin/env bash

# generate_password() {
#     read -p "Яка кількість символів? " SYMBOLS
#     # openssl rand -base64 ${SYMBOLS} | tr -d '/+=' | cut -c1-${SYMBOLS}
#     openssl rand -base64 ${SYMBOLS} | tr -d '/+=' | cut -c1-${SYMBOLS}
# }
#
# generate_password

# НАЛАШТУВАННЯ
set -Eeuo pipefail

# Дозволені символи для генерації секрету
readonly CHARSET='A-Za-z0-9!@#$%^&*()_+=-'

SYMBOLS="${1:-}"
if [[ -z "${SYMBOLS}" ]]; then
    read -rp "Яка кількість символів? " SYMBOLS
fi

# ФУНКЦІЯ ГЕНЕРАЦІЇ СЕКРЕТУ
generate_secret() {
    local length="$1"
    local secret=""

    # Перевіряємо, що довжина є додатним числом
    if ! [[ "${length}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Помилка: довжина секрету повинна бути додатним числом." >&2
        return 1
    fi

    # Генеруємо символи доти, доки не отримаємо
    # необхідну кількість символів
    while (( ${#secret} < length )); do

        secret+="$(
            openssl rand -base64 64 |
            tr -dc "${CHARSET}"
        )"

    done

    # Виводимо рівно потрібну кількість символів
    printf '%s\n' "${secret:0:length}"
}

# ГЕНЕРАЦІЯ СЕКРЕТУ
readonly SECRET="$(generate_secret "${SYMBOLS}")"

# РЕЗУЛЬТАТ
echo "${SECRET}"
echo "Length: ${#SECRET}"
