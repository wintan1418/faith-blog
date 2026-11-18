# frozen_string_literal: true

# The thank-you and receipt a giver gets once Paystack confirms their gift.
class DonationMailer < ApplicationMailer
  def thank_you(donation)
    @donation = donation
    @first_name = donation.name.to_s.split.first unless donation.anonymous
    mail(to: donation.email, subject: "Thank you for your gift to Brethreign")
  end
end
