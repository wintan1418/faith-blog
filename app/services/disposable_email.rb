# frozen_string_literal: true

# Throwaway email services (config/disposable_email_domains.txt, from the
# community-maintained disposable-email-domains list) — rejected at sign-up.
module DisposableEmail
  LIST_PATH = Rails.root.join("config/disposable_email_domains.txt")

  module_function

  def domains
    @domains ||= File.readlines(LIST_PATH, chomp: true)
                     .map { |line| line.strip.downcase }
                     .reject { |line| line.empty? || line.start_with?("#") }
                     .to_set
                     .freeze
  end

  # Matches the domain and any parent domain (mail.foo.tempmail.com → tempmail.com).
  def disposable?(email)
    domain = email.to_s.downcase.split("@", 2)[1].to_s.strip
    return false if domain.empty?

    parts = domain.split(".")
    (0..parts.size - 2).any? { |i| domains.include?(parts[i..].join(".")) }
  end
end
