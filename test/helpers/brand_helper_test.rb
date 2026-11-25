require "test_helper"

class BrandHelperTest < ActionView::TestCase
  include IconHelper

  test "the logomark is the brand pack B: two halos and the solid mark" do
    svg = Nokogiri::HTML.fragment(brand_mark_svg("x")).at("svg")
    assert_equal "0 0 261.9 400", svg["viewbox"]
    assert_equal %w[0.2 0.6], svg.css("path[fill-opacity]").map { _1["fill-opacity"] }
    assert_equal 3, svg.css("path").size
  end

  test "the Breathe icon wears the new mark, not the old wave" do
    html = render_icon("breathe", classes: "h-5 w-5")
    assert_includes html, BrandHelper::MARK_PATHS.last.last
    assert_not_includes html, "M3.5 13c"
  end

  test "no template still draws the old wave logo" do
    old = [ "M3.5 13c2.2-4.5", "176 208, 224 208", "M7 19 C 11 13", "M14 39 C 22 27", "M26 70 C 41 47" ]
    files = Dir[Rails.root.join("{app,lib,public}/**/*.{erb,svg,html,css,js,rb}")].reject { _1.include?("/builds/") }
    offenders = files.select { |f| old.any? { File.read(f).include?(_1) } }
    assert_empty offenders.map { _1.delete_prefix("#{Rails.root}/") }
  end
end
