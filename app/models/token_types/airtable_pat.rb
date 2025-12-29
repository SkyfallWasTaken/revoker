module TokenTypes
  class AirtablePAT < Base
    self.regex = /\Apat[a-zA-Z0-9]{5,}\.[0-9a-fA-F]{10,}\z/
    self.name = "Airtable Personal Access Token"
    self.hint = "pat..."

    def self.revoke(token, **kwargs)
      # TODO: implement real Airtable API call to revoke token
      { success: true, owner_email: "owner@example.com", status: :action_needed }
    end

    # Redact: show prefix + dot, then first 3 and last 3 of hash
    def self.redact(token)
      return "" if token.nil? || token.empty?

      parts = token.split(".", 2)
      return token if parts.length != 2

      prefix = parts[0]
      hash = parts[1]

      return token if hash.length <= 6

      "#{prefix}.#{hash[0..2]}#{"*" * (hash.length - 6)}#{hash[-3..]}"
    end
  end
end
