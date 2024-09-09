#!/bin/bash

set -eu

export GITHUB_TOKEN=${1}
export DIRECTORY_PATH=${2}
export GITHUB_REPO=${3}

cd /home/dependabot/dependabot-waf-runner && bundle exec ruby ./update.rb