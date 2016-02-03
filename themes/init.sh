#!/usr/bin/env bash
# ==============================================================================
# Init Themes!
# ==============================================================================

function initTheme {
  local C_DIR=$(dirname $(readlink -f $0))
  local BACKGROUND_DIR=$C_DIR/hexo-theme-yelee/source/background

  if [[ -d $BACKGROUND_DIR ]]
  then
    rm -rvf $BACKGROUND_DIR/*
  fi

  return $?
}

initTheme

