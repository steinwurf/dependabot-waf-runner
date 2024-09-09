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
    steps:
      - uses: steinwurf/dependabot-waf-runner@master
        with:
          token: ${{ github.token }}
          repository: ${{ github.repository }}
          directory: '/' # can be ommited
          registries: '' # can be ommited
```
