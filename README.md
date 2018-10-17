# Bugzillabot

Bugzillabot automatically manages NEEDSINFO bugs.

# Requires

- Ruby 2.4+

# Configuration

Configuration is supplied by `.config.yaml` inside the git working directory
or by `~/.config/bugzillabot.yaml`. The config contains a hash of "type" keys
which contain a hash of the actual config values of a given run type.
See `test/config.yaml` for an example.

# Run Types

By default bugzillabot runs in TESTING mode which means it uses the `testing`
type config. This should be used to validate behavior against a staging
bugzilla instance. If all is good bugzillabot can be run with the environment
variable `PRODUCTION=1` to switch it into production mode.

# Installation

- `bundle install`
- create a .config.yaml or user-level config
- add testing settings to config
- add production settings to config
- validate against testing
- `PRODUCTION=1 bin/bugzillabot`

# Debugging

You can enable HTTP level debugging by setting `DEBUG=1` in the environment.
