# dependabot-waf-runner
The dependabot update script to deploy

## Example for a workflow
```yml
name: Daily Scheduled Bump
on:
  workflow_dispatch:
  schedule:
    - cron: '00 00 * * 1-5'

jobs:
  update:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/steinwurf/dependabot-waf-runner:master
      env:
        LOCAL_GITHUB_ACCESS_TOKEN: ${{ secrets.LOCAL_GITHUB_ACCESS_TOKEN }}
        GITHUB_REPO: ${{ github.repository }}
    steps:
      - name: Update dependencies
        run: cd /home/dependabot/dependabot-waf-runner && bundle exec ruby ./update.rb

```
