FROM ghcr.io/steinwurf/dependabot-updater-waf:latest

ARG CODE_DIR=/home/dependabot/dependabot-waf-runner
RUN mkdir -p ${CODE_DIR}
COPY --chown=dependabot:dependabot Gemfile ${CODE_DIR}/
WORKDIR ${CODE_DIR}

run bundle config set --local path "vendor" \
    && bundle install --jobs 4 --retry 3

COPY --chown=dependabot:dependabot . ${CODE_DIR}

CMD ["bundle", "exec", "ruby", "./update.rb"]