module TokenTypes
  class SlackXoxp < Base
    self.regex = /\Axoxp-[a-zA-Z0-9]+-[a-zA-Z0-9]+-[a-zA-Z0-9]+-[a-zA-Z0-9]+\z/
    self.name = "Slack bot user OAuth token"
    self.hint = "xoxp-..."

    def self.revoke(token, **kwargs)
      Rails.logger.info("SlackXoxp: Starting revocation for token")

      client = Slack::Web::Client.new(token:)

      # Step 1: Verify the token and get user info using auth.test
      Rails.logger.info("SlackXoxp: Calling auth.test")
      test_response = client.auth_test
      Rails.logger.info("SlackXoxp: auth.test response: ok=#{test_response.ok}, user=#{test_response.user}, user_id=#{test_response.user_id}")

      user_id = test_response.user_id
      username = test_response.user
      Rails.logger.info("SlackXoxp: Got user_id: #{user_id}, username: #{username}")

      # Step 2: Get detailed user info using users.info with a privileged token
      owner_email = username
      owner_slack_id = user_id
      bot_token = ENV["SLACK_BOT_TOKEN"]
      if bot_token
        Rails.logger.info("SlackXoxp: Calling users.info with bot token for user: #{user_id}")
        bot_client = Slack::Web::Client.new(token: bot_token)
        user_response = bot_client.users_info(user: user_id)
        Rails.logger.info("SlackXoxp: users.info response: ok=#{user_response.ok}")

        if user_response.ok && user_response.user.profile.email
          owner_email = user_response.user.profile.email
          Rails.logger.info("SlackXoxp: Got owner_email: #{owner_email}")
        else
          Rails.logger.warn("SlackXoxp: users.info failed or no email, falling back to username")
        end
      else
        Rails.logger.warn("SlackXoxp: SLACK_BOT_TOKEN not configured, using username")
      end

      # Step 3: Revoke the token using auth.revoke
      Rails.logger.info("SlackXoxp: Calling auth.revoke")
      revoke_response = client.auth_revoke
      Rails.logger.info("SlackXoxp: auth.revoke response: ok=#{revoke_response.ok}")

      unless revoke_response.ok
        Rails.logger.warn("SlackXoxp: auth.revoke failed")
        return { success: false }
      end

      Rails.logger.info("SlackXoxp: Token successfully revoked")
      { success: true, owner_email:, owner_slack_id: }
    rescue StandardError => e
      Rails.logger.error("SlackXoxp: Exception during revocation - #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      { success: false }
    end

    # Redact: show first segment, hide middle segments, show last 4 of final segment
    def self.redact(token)
      return "" if token.nil? || token.empty?

      parts = token.split("-")
      return token if parts.length < 4

      first = parts[0]
      last_segment = parts[-1]
      last_chars = last_segment.length >= 4 ? last_segment[-4..] : last_segment

      # Use asterisks matching the length of hidden portions
      part1_hidden = "*" * (parts[1].length - 2)
      part2_hidden = "*" * parts[2].length
      part3_hidden = "*" * (parts[3].length - last_chars.length)

      "#{first}-#{parts[1][0..1]}#{part1_hidden}-#{part2_hidden}-#{part3_hidden}#{last_chars}"
    end
  end
end
