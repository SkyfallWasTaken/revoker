# the revoker

web app for revoking leaked tokens. paste in a token and it automatically detects the type, revokes it, and notifies the owner.

## what this does

when tokens get leaked in repos, logs, or slack messages, this tool streamlines the revocation process. it identifies the token type and handles the revocation without manual intervention.

supported token types:
- slack tokens (xoxb, xoxp, xoxc, xoxd)
- airtable PATs
- theseus API keys

## setup

rails 8 + svelte on vite.

```bash
bundle install
yarn install
```

## env vars you need

### required

**airtable** (where revocations get stored):
- `AIRTABLE_BASE_KEY` - the base ID where you're tracking revocations
- `AIRTABLE_PAT` - your airtable personal access token

**slack** (for revoking slack tokens + sending notifications):
- `SLACK_BOT_TOKEN` - a bot token with `users:read`, `users:read.email` scopes
- `SLACK_ADMIN_TOKEN` - admin token for looking up who installed apps (needs `admin` scope)

### optional but useful

**notifications**:
- `NORA_SLACK_ID` - your slack user ID, gets CC'd on all notifications
- `LOOPS_API_KEY` - for sending email notifications via loops
- `LOOPS_ACTION_NEEDED_TRANSACTIONAL_ID` - loops template ID for "action needed" emails
- `LOOPS_REVOKED_TRANSACTIONAL_ID` - loops template ID for "token revoked" emails

**theseus** (if you're revoking theseus tokens):
- `THESEUS_API_URL` - where your theseus instance lives
- `THESEUS_AUTH_TOKEN` - auth header for hitting the revoke endpoint

**misc**:
- `APP_HOST` - base URL for the app (defaults to `http://localhost:3000`)
- `SENTRY_DSN` - if you want error tracking
- `SENTRY_TRACES_SAMPLE_RATE` - defaults to 0.1
- `SENTRY_PROFILES_SAMPLE_RATE` - defaults to 0.1

## running it

```bash
bin/dev
```

this starts rails + vite together via foreman.

## how it works

1. user submits a token
2. app detects token type via regex matching
3. calls the appropriate API to revoke the token
4. creates a revocation record in airtable
5. sends notifications via slack DM and email
6. prompts for additional context (submitter, reason, etc)

## adding token types

if you run a service and want to add support for your tokens, create a new class in `app/models/token_types/`:

```ruby
module TokenTypes
  class YourServiceToken < Base
    # regex to match your token format
    self.regex = /\Ayour-prefix-[a-zA-Z0-9]+\z/

    # display name shown to users
    self.name = "Your Service API Token"

    # hint shown in the UI
    self.hint = "your-prefix-..."

    # optional: emails to CC on revocation notifications
    self.service_owner_emails = ["security@yourservice.com"]

    # implement revocation logic
    def self.revoke(token, **kwargs)
      # call your API to revoke the token
      # return { success: true, owner_email: "user@example.com" }
      # or { success: true, owner_email: "...", status: "action_needed" }
      # or { success: false } if it's not your token
      #
      # optional: include key_name to identify which specific key/token was revoked
      # return { success: true, owner_email: "...", key_name: "prod-api-key" }
      # for bots, use the bot name. this shows up in notifications to help users
      # identify which token was compromised
    end

    # optional: custom redaction logic
    def self.redact(token)
      # default shows first 7 chars + asterisks + last 3
      # override if you need different behavior
      super
    end
  end
end
```

then add your token type to the registry in `app/models/token_types.rb`:

```ruby
ALL = [
  AirtablePAT,
  SlackXoxb,
  # ... other types
  YourServiceToken  # add here
].freeze
```

the `revoke` method should:
- call your service's API to invalidate the token
- return the owner's email if possible (for notifications)
- return `status: "action_needed"` if manual intervention is required
- optionally return `key_name` to identify the specific key (e.g., msw@hackatime)
- handle errors gracefully and return `{ success: false }` on failure

the `key_name` field is optional but really nice to have. 