#!/usr/bin/env bash

function github_fetch_file {
    
}

# Prompt user for installation directory or use default
read -p "Installation directory (default $HOME/oradatadog)? " USER_INSTALL_DIR
INSTALL_DIR=${USER_INSTALL_DIR:-$HOME/oradatadog}
echo $INSTALL_DIR

# Ensure installation directory exists
mkdir -p $INSTALL_DIR