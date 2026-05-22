#!/usr/bin/env bash

configure_proxy_env() {
  export http_proxy="${http_proxy:-${HTTP_PROXY:-}}"
  export https_proxy="${https_proxy:-${HTTPS_PROXY:-}}"
  export all_proxy="${all_proxy:-${ALL_PROXY:-}}"
  export no_proxy="${no_proxy:-${NO_PROXY:-localhost,127.0.0.1,::1}}"

  export HTTP_PROXY="${HTTP_PROXY:-${http_proxy:-}}"
  export HTTPS_PROXY="${HTTPS_PROXY:-${https_proxy:-}}"
  export ALL_PROXY="${ALL_PROXY:-${all_proxy:-}}"
  export NO_PROXY="${NO_PROXY:-${no_proxy:-localhost,127.0.0.1,::1}}"

  local git_proxy="${HTTPS_PROXY:-${HTTP_PROXY:-${ALL_PROXY:-}}}"
  if [[ -n "${git_proxy}" ]]; then
    git config --global http.proxy "${git_proxy}"
    git config --global https.proxy "${git_proxy}"
  fi
}

print_proxy_env() {
  if [[ -n "${HTTP_PROXY:-}${HTTPS_PROXY:-}${ALL_PROXY:-}" ]]; then
    echo "Proxy enabled for downloads. HTTP_PROXY=$(mask_proxy_url "${HTTP_PROXY:-}") HTTPS_PROXY=$(mask_proxy_url "${HTTPS_PROXY:-}") ALL_PROXY=$(mask_proxy_url "${ALL_PROXY:-}")"
  else
    echo "Proxy disabled for downloads."
  fi
}

mask_proxy_url() {
  local proxy_url="$1"
  if [[ -z "${proxy_url}" ]]; then
    echo "<empty>"
    return
  fi

  echo "${proxy_url}" | sed -E 's#(://)[^/@]+@#\1***@#'
}