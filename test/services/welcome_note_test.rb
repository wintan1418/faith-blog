# frozen_string_literal: true

require "test_helper"

class WelcomeNoteTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    pass = SecureRandom.base58(16)
    @founder = User.create!(username: "wintan_founder", email: "founder@example.com", password: pass, role: :super_admin)
    @member = User.create!(username: "new_brother", email: "brother@example.com", password: pass)
    @member.update_column(:welcomed_at, nil)
    ActionMailer::Base.deliveries.clear
  end

  test "a new member gets the email and a note in their inbox from the founder" do
    perform_enqueued_jobs { WelcomeNote.deliver(@member) }

    assert_equal 1, ActionMailer::Base.deliveries.size, "only the welcome email, not a new-message email too"
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "brother@example.com" ], mail.to
    assert_equal "Welcome home, new_brother", mail.subject
    assert_includes mail.text_part.body.to_s, "Psalm 133:1"
    assert_includes mail.text_part.body.to_s, "Oluwadare Juwon (Wintan)"

    conversation = Conversation.between(@founder, @member)
    assert conversation
    note = conversation.messages.last
    assert_equal @founder, note.sender
    assert_includes note.body, "Dear new_brother"
    assert @member.reload.welcomed_at
  end

  test "it is sent only once" do
    WelcomeNote.deliver(@member)
    assert_no_enqueued_emails { WelcomeNote.deliver(@member.reload) }
    assert_equal 1, Conversation.between(@founder, @member).messages.count
  end

  test "existing members get an opening that fits them" do
    assert_includes WelcomeNote.inbox_text(@member, existing: true), "Whether you joined last week"
    assert_includes WelcomeNote.inbox_text(@member, existing: false), "You've just joined a family"
  end

  test "no email when the member switched emails off, but the inbox note still arrives" do
    @member.update_column(:email_notifications_enabled, false)
    assert_no_enqueued_emails { WelcomeNote.deliver(@member) }
    assert Conversation.between(@founder, @member)
  end

  test "suspended members are skipped" do
    @member.update_column(:active, false)
    WelcomeNote.deliver(@member)
    assert_nil @member.reload.welcomed_at
  end
end
