module TokenTypes
  class SlackXoxc < Base
    self.regex = /\Axoxc-\d+-\d+-\d+-[a-fA-F0-9]{64}\z/
    self.name = "scraped Slack client token"
    self.hint = "xoxc-..."

    def self.revoke(token, **kwargs)
      xoxd = kwargs[:xoxd]

      Rails.logger.info("SlackXoxc: Starting revocation for xoxc token")

      # xoxc tokens require the xoxd cookie to work
      unless xoxd.present?
        Rails.logger.warn("SlackXoxc: xoxc tokens require xoxd cookie for API calls")
        return {
          success: false,
          error: "xoxc tokens require the matching xoxd cookie. Please provide both tokens together."
        }
      end

      # xoxc tokens don't work with standard Slack Web API, so we skip auth.test
      # and use the client.userBoot endpoint instead to get user info
      begin
        # Get workspace domain from environment variable or use default
        workspace_domain = ENV["SLACK_WORKSPACE_DOMAIN"] || "hackclub.enterprise.slack.com"

        # First, try to get the user email using client.userBoot
        owner_email = "unknown"
        owner_slack_id = nil

        begin
          Rails.logger.info("SlackXoxc: Attempting to get user email via client.userBoot")
          boot_url = "https://#{workspace_domain}/api/client.userBoot"

          connection = Faraday.new do |f|
            f.request :multipart
            f.request :url_encoded
            f.adapter Faraday.default_adapter
          end

          headers = {
            "User-Agent" => "revoker/1.0",
            "Accept" => "*/*"
          }

          # Add xoxd cookie if provided
          if xoxd.present?
            cookie_value = CGI.escape(xoxd)
            Rails.logger.info("SlackXoxc: Including xoxd cookie in userBoot request")
            Rails.logger.info("SlackXoxc: xoxd length=#{xoxd.length}, encoded length=#{cookie_value.length}")
            headers["Cookie"] = "d=#{cookie_value}"
          end

          boot_response = connection.post(boot_url) do |req|
            req.headers = headers
            req.body = {
              token: token,
              _x_sonic: "true"
            }
          end

          Rails.logger.info("SlackXoxc: client.userBoot response: status=#{boot_response.status}")

          if boot_response.status == 200
            boot_json = JSON.parse(boot_response.body)
            if boot_json["ok"] && boot_json.dig("self", "profile", "email")
              owner_email = boot_json.dig("self", "profile", "email")
              owner_slack_id = boot_json.dig("self", "id")
              Rails.logger.info("SlackXoxc: Got user email: #{owner_email}, user_id: #{owner_slack_id}")
            else
              Rails.logger.warn("SlackXoxc: client.userBoot succeeded but no email found in response")
            end
          else
            Rails.logger.warn("SlackXoxc: client.userBoot HTTP error #{boot_response.status}")
          end
        rescue => e
          Rails.logger.warn("SlackXoxc: Failed to get email via client.userBoot: #{e.message}")
        end

        # Now proceed with revocation
        revoke_url = "https://#{workspace_domain}/api/auth.enterpriseSignout"
        Rails.logger.info("SlackXoxc: Using revoke endpoint: #{revoke_url}")

        # Revoke using undocumented endpoint with Faraday
        Rails.logger.info("SlackXoxc: Calling auth.enterpriseSignout")

        connection = Faraday.new do |f|
          f.request :multipart
          f.request :url_encoded
          f.adapter Faraday.default_adapter
        end

        headers = {
          "User-Agent" => "revoker/1.0",
          "Accept" => "*/*"
        }

        # Add xoxd cookie if provided
        if xoxd.present?
          cookie_value = CGI.escape(xoxd)
          Rails.logger.info("SlackXoxc: Including xoxd cookie in request")
          Rails.logger.info("SlackXoxc: xoxd length=#{xoxd.length}, encoded length=#{cookie_value.length}")
          headers["Cookie"] = "d=#{cookie_value}"
        end

        response = connection.post(revoke_url) do |req|
          req.headers = headers
          req.body = {
            token: token,
            _x_sonic: "true",
            _x_app_name: "client"
          }
        end

        Rails.logger.info("SlackXoxc: auth.enterpriseSignout response: status=#{response.status}, body=#{response.body[0..200]}")

        revocation_succeeded = false

        if response.status == 200
          # Try to parse JSON response
          begin
            json_response = JSON.parse(response.body)
            if json_response["ok"]
              Rails.logger.info("SlackXoxc: Token successfully revoked via auth.enterpriseSignout")
              revocation_succeeded = true
            else
              Rails.logger.warn("SlackXoxc: auth.enterpriseSignout failed: #{json_response["error"]}")
            end
          rescue JSON::ParserError
            # Response might not be JSON, check if it looks successful
            if response.body.include?("ok") || response.body.empty?
              Rails.logger.info("SlackXoxc: Token likely revoked via auth.enterpriseSignout (non-JSON response)")
              revocation_succeeded = true
            else
              Rails.logger.warn("SlackXoxc: Unexpected response format from auth.enterpriseSignout")
            end
          end
        else
          Rails.logger.warn("SlackXoxc: auth.enterpriseSignout HTTP error #{response.status}")
        end

        # If auth.enterpriseSignout failed, try auth.revoke as fallback
        unless revocation_succeeded
          Rails.logger.info("SlackXoxc: Trying auth.revoke as fallback")

          auth_revoke_url = "https://#{workspace_domain}/api/auth.revoke"

          revoke_response = connection.post(auth_revoke_url) do |req|
            req.headers = headers
            req.body = { token: token }
          end

          Rails.logger.info("SlackXoxc: auth.revoke response: status=#{revoke_response.status}, body=#{revoke_response.body[0..200]}")

          if revoke_response.status == 200
            begin
              revoke_json = JSON.parse(revoke_response.body)
              if revoke_json["ok"] || revoke_json["revoked"]
                Rails.logger.info("SlackXoxc: Token successfully revoked via auth.revoke")
                revocation_succeeded = true
              else
                Rails.logger.warn("SlackXoxc: auth.revoke failed: #{revoke_json["error"]}")
              end
            rescue JSON::ParserError
              if revoke_response.body.include?("ok") || revoke_response.body.include?("revoked")
                Rails.logger.info("SlackXoxc: Token likely revoked via auth.revoke")
                revocation_succeeded = true
              end
            end
          else
            Rails.logger.warn("SlackXoxc: auth.revoke HTTP error #{revoke_response.status}")
          end
        end

        if revocation_succeeded
          return { success: true, owner_email:, owner_slack_id: }
        else
          Rails.logger.error("SlackXoxc: Both auth.enterpriseSignout and auth.revoke failed")

          # If we got the user email, return success with action_needed status
          if owner_email.present? && owner_email != "unknown"
            Rails.logger.info("SlackXoxc: Returning action_needed status with email")
            return {
              success: true,
              status: :action_needed,
              owner_email:,
              owner_slack_id:
            }
          end

          return { success: false }
        end

      rescue Faraday::Error => e
        Rails.logger.error("SlackXoxc: Faraday error - #{e.message}")
        return { success: false }
      rescue StandardError => e
        Rails.logger.error("SlackXoxc: Exception during revocation - #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        return { success: false }
      end
    end

    # Redact: show first segment, partially show second, hide rest except last 4 chars
    def self.redact(token)
      return "" if token.nil? || token.empty?

      parts = token.split("-")
      return token if parts.length < 5

      first = parts[0]
      last_segment = parts[-1]
      last_chars = last_segment.length >= 4 ? last_segment[-4..] : last_segment

      # Use asterisks matching the length of hidden portions
      part1_hidden = "*" * (parts[1].length - 2)
      part2_hidden = "*" * parts[2].length
      part3_hidden = "*" * parts[3].length
      part4_hidden = "*" * (parts[4].length - last_chars.length)

      "#{first}-#{parts[1][0..1]}#{part1_hidden}-#{part2_hidden}-#{part3_hidden}-#{part4_hidden}#{last_chars}"
    end
  end
end
