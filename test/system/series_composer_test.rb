# frozen_string_literal: true

require "application_system_test_case"

# The composer's "Part of a series" row: typing the next part's title offers
# to start a series with the earlier parts, and the room picker still opens.
class SeriesComposerSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @writer = create_member("series_sys_writer", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i)
    @room = Room.create!(name: "Series Sys Room", description: "x", is_public: true, position: 0)
    @one = breath("THE INHERITANCE (#1)")
    @two = breath("THE INHERITANCE (#2)")
    login_as @writer, scope: :user
  end

  teardown do
    Warden.test_reset!
    ENV.delete("AI_MODERATION_STUB")
  end

  def breath(title)
    Post.create!(user: @writer, title: title, content: "Words for #{title}.", status: :published, moderation_status: :approved)
  end

  test "the next part's title offers the series, and the room picker still works" do
    open_composer
    within "dialog.fc-composer-dialog" do
      find("input[name='post[title]']").fill_in(with: "THE INHERITANCE (#3)")
      assert_selector ".eg-cmp-series-hint", text: "Looks like part 3 of “THE INHERITANCE”", wait: 5
      click_on "Add"
      assert_no_selector ".eg-cmp-series-hint"
      assert_equal "new", find("select[name='post[series_id]']").value
      assert_equal "THE INHERITANCE", find("input[name='post[new_series_title]']").value

      # A real click: fails if anything (an ::after tap area) covers the select.
      find("select[name='post[room_id]']").click
      find("select[name='post[room_id]']").select("Series Sys Room")
    end
    page.execute_script("document.querySelector('dialog trix-editor').editor.insertString(arguments[0])",
                        "The third part of the inheritance.")
    find("dialog button[type=submit][value=published]").click
    assert_no_selector "dialog.fc-composer-dialog[open]", wait: 10

    series = @writer.series.find_by!(title: "THE INHERITANCE")
    third = @writer.posts.order(:id).last
    assert_equal [ @one.id, @two.id, third.id ], series.posts.pluck(:id)
    assert_equal @room, third.room
  end

  test "picking New series reveals the name field" do
    open_composer
    within "dialog.fc-composer-dialog" do
      assert_no_selector "input[name='post[new_series_title]']"
      find("select[name='post[series_id]']").select("New series…")
      assert_selector "input[name='post[new_series_title]']"
    end
  end

  private

  def open_composer
    visit feed_path
    page.execute_script(%(document.querySelector("[data-action~='click->composer-modal#open']").click()))
    find("dialog.fc-composer-dialog trix-editor", visible: true)
  end
end
