#!/bin/bash
###############################################################################
#
#Company : Liyang Milian Electronic Technology Co., Ltd.
#Brand: 米联客(msxbo)
#Technical forum:uisrc.com
#taobao: osrc.taobao.com
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
###############################################################################
# => Writing a Warning Message to the Console Window
echo_warn() {
  local msg="$1"
  printf "\033[33m[WARNING] \033[0m";
  printf "$msg\n";
}
export -f echo_warn

# => Writing a Infomation Message to the Console Window
echo_info() {
  local msg="$1"
  printf "\033[32m[INFO] \033[0m";
  printf "$msg\n";
}
export -f echo_info

# => Writing a Error Message to the Console Window
echo_error() {
  local msg="$1"
  printf "\033[31m[ERROR] \033[0m";
  printf "$msg\n";
}
export -f echo_error

# => Writing a Warning Message to the Console Window
print_warn() {
  local msg="$1"
  printf "\033[33m$msg\033[0m";
}
export -f print_warn

# => Writing a Infomation Message to the Console Window
print_info() {
  local msg="$1"
  printf "\033[32m$msg\033[0m";
}
export -f print_info

# => Writing a Error Message to the Console Window
print_error() {
  local msg="$1"
  printf "\033[31m$msg\033[0m";
}
export -f print_error

# => Writing a Error Message to the Console Window and exit
error_exit() {
  local msg="$1"
  printf "\033[31m[ERROR] \033[0m";
  printf "$msg\n";
  exit 1;
}
export -f error_exit
