#!/usr/bin/env bash
# ==============================================================================
# Init Themes!
# ==============================================================================
set -ex

THEME_DIR=$(dirname $(readlink -f $0))

function _hexo_theme_yelee ()
{
  local BACKGROUND_DIR="${THEME_DIR}/hexo-theme-yelee/source/background"

  if [[ -d $BACKGROUND_DIR ]]
  then
    rm -rf ${BACKGROUND_DIR}
    mkdir -p ${BACKGROUND_DIR}
  fi

  return $?
}

function initTheme ()
{
  _hexo_theme_yelee

  return $?
}

initTheme

