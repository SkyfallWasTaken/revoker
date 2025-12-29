module TokenTypes
  class TheseusPublicAPIKey < TheseusBase
    self.regex = /\Ath_apk_(live|dev)_[a-zA-Z0-9]{20,}\z/
    self.name = "mail.hackclub.com public API Key"
    self.hint = "th_apk_live_..."

    # Redact: show prefix + env + first 3 of random, then asterisks, then checksum
    # Example: th_apk_live_abc***7
    def self.redact(token)
      return "" if token.nil? || token.empty?

      return "" if token.nil? || token.empty?
      return token if token.length <= 13  # "th_apk_live_" is 12 chars

      parts = token.split("_")
      return token if parts.length < 4

      prefix = parts[0..2].join("_")
      data = parts[3]

      "#{prefix}_#{data[0..2]}#{"*" * [data.length - 5, 3].max}#{data[-2..]}"
    end
  end
end
