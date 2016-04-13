#!/usr/bin/env bash
# ==============================================================================
# Clone It!
# ==============================================================================

function doClone
{
  local C_DIR=$(dirname $(readlink -f $0))
  local GIT_DIR=$C_DIR/.deploy_git

  cd $C_DIR

  if ! type git >/dev/null 2>&1
  then
    echo "failed: git is needed but not found, quit."
    return 1
  else
    if [[ ! -d $GIT_DIR ]]
    then
      env rm -f $GIT_DIR
      env git clone -b master https://github.com/Arondight/arondight.github.io.git $(basename $GIT_DIR)
    fi
  fi

  return $?
}

doClone

if [[ 0 -ne $? ]]
then
  exit $?
fi

