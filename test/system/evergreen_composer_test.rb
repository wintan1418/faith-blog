# frozen_string_literal: true

require "application_system_test_case"

# The Evergreen "New breath" composer: the Breath / Prayer / Verse / Thread
# switch sets the right fields, the Schedule switch reveals its picker, and a
# prayer posts as a prayer request.
class EvergreenComposerSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    @member = create_member("evergreen_writer", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i)
    login_as @member, scope: :user
  end

  teardown { Warden.test_reset! }

  test "the kind switch sets kind, prayer status and the thread title" do
    open_composer
    within "dialog.fc-composer-dialog" do
      kind = find("input[name='post[kind]']", visible: :all)
      prayer = find("input[name='post[prayer_status]']", visible: :all)
      title = find("input[name='post[title]']")

      find("button[role=radio][data-mode=prayer]").click
      assert_selector "button[role=radio][data-mode=prayer][aria-checked=true]"
      assert_equal "breath", kind.value
      assert_equal "prayer_pending", prayer.value

      find("button[role=radio][data-mode=thread]").click
      assert_equal "thread", kind.value
      assert_equal "not_a_prayer", prayer.value
      assert_equal true, title.evaluate_script("this.required")
      assert_selector "button[type=submit][value=published]", text: "Open the thread"

      find("button[role=radio][data-mode=verse]").click
      assert_equal "breath", kind.value
      assert_equal false, title.evaluate_script("this.required")
      assert_selector "button[type=submit][value=published]", text: "Breathe"
    end
  end

  test "the Schedule switch reveals the picker and switching it off clears the time" do
    open_composer
    within "dialog.fc-composer-dialog" do
      assert_no_selector "input[type=datetime-local]"
      find(".eg-cmp-schedule [role=switch]").click
      assert_selector "input[type=datetime-local]"
      page.execute_script(<<~JS)
        const input = document.querySelector("dialog input[type=datetime-local]")
        const d = new Date(Date.now() + 3 * 3600 * 1000)
        const pad = (n) => String(n).padStart(2, "0")
        input.value = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
        input.dispatchEvent(new Event("change", { bubbles: true }))
      JS
      assert_selector "button[type=submit][value=published]", text: "Schedule"
      assert_not_empty find("input[name='post[scheduled_for]']", visible: :all).value

      find(".eg-cmp-schedule [role=switch]").click
      assert_no_selector "input[type=datetime-local]"
      assert_empty find("input[name='post[scheduled_for]']", visible: :all).value
      assert_selector "button[type=submit][value=published]", text: "Breathe"
    end
  end

  test "a prayer posts as a prayer request" do
    open_composer
    find("dialog button[role=radio][data-mode=prayer]").click
    page.execute_script("document.querySelector('dialog trix-editor').editor.insertString(arguments[0])",
                        "Please pray for my mother's surgery on Thursday.")
    assert_difference -> { @member.posts.count }, 1 do
      find("dialog button[type=submit][value=published]").click
      assert_no_selector "dialog.fc-composer-dialog[open]", wait: 10
    end
    assert @member.posts.order(:id).last.prayer_status_prayer_pending?
  end

  private

  def open_composer
    visit feed_path
    page.execute_script(%(document.querySelector("[data-action~='click->composer-modal#open']").click()))
    find("dialog.fc-composer-dialog trix-editor", visible: true)
    assert page.evaluate_async_script(<<~JS), "editor never loaded"
      const done = arguments[arguments.length - 1]
      const el = document.querySelector("dialog.fc-composer-dialog trix-editor")
      const wait = (n) => el.editor ? done(true) : n ? setTimeout(() => wait(n - 1), 100) : done(false)
      wait(50)
    JS
  end
end
