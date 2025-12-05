class BrethrenCard < ApplicationRecord
  belongs_to :user

  validates :church_or_assembly, presence: true, on: :update
  validates :bio, presence: true, length: { maximum: 500 }, on: :update
  validates :occupation, presence: true, on: :update
  validates :whatsapp_number, presence: true, on: :update
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, on: :update

  before_save :check_completeness

  def whatsapp_link
    return nil unless whatsapp_number.present?
    # Remove non-digits and create WhatsApp link
    clean_number = whatsapp_number.gsub(/\D/, '')
    "https://wa.me/#{clean_number}"
  end

  def gmail_link
    return nil unless email.present?
    "mailto:#{email}"
  end

  def complete?
    is_complete
  end

  private

  def check_completeness
    # Card is complete when all required text fields are filled
    # Profile photo is recommended but not required
    self.is_complete = [
      church_or_assembly.present?,
      bio.present?,
      occupation.present?,
      whatsapp_number.present?,
      email.present?
    ].all?
  end
end

