#!/bin/bash

set -eu

export GITHUB_TOKEN=${1}
export GITHUB_MAVEN_REGISTRIES=${2}
export DIRECTORY_PATH=${3}
export GITHUB_REPO=${4}

cd /home/dependabot/dependabot-waf-runner && bundle exec ruby ./update.rb