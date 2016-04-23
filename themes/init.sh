#!/usr/bin/env bash
# ==============================================================================
# Init Themes!
# ==============================================================================

function _hexo_theme_yelee ()
{
  [[ -z $THEME_DIR ]] && local THEME_DIR=$(dirname $(readlink -f $0))
  local BACKGROUND_DIR=${THEME_DIR}/hexo-theme-yelee/source/background

  if [[ -d $BACKGROUND_DIR ]]
  then
    rm -rvf ${BACKGROUND_DIR}/*
  fi

  return $?
}

function initTheme ()
{
  _hexo_theme_yelee

  return $?
}

initTheme

