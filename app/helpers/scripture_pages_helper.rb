# frozen_string_literal: true

module ScripturePagesHelper
  # The opening words of a verse, for titles: "I will set no wicked thing
  # before mine eyes" (stops at the first clause break, max ~60 characters).
  def scripture_snippet(text, max: 60)
    text = text.to_s.squish.sub(/\A¶\s*/, "")
    return "" if text.blank?

    clause = text.split(/(?<=[;:,.?!])\s+/).inject("") do |acc, part|
      break acc if acc.split.size >= 5

      [ acc, part ].compact_blank.join(" ")
    end
    clause = clause.sub(/[;:,.]+\z/, "")
    clause.length > max ? clause.truncate(max, separator: " ", omission: "…") : clause
  end

  # "Psalm 101:3 — “I will set no wicked thing before mine eyes” (KJV): Meaning and Context"
  def scripture_page_title(reference, passage)
    snippet = scripture_snippet(passage.primary.first&.last)
    return "#{reference} (KJV): Meaning and Context" if snippet.blank?

    "#{reference} — “#{snippet}” (KJV): Meaning and Context"
  end

  def scripture_meta_description(reference, passage, insight)
    return insight.summary.truncate(158, separator: " ") if insight&.summary.present?

    text = passage.primary_text
    if text.present?
      "#{reference} (KJV): “#{text.squish.truncate(95, separator: ' ', omission: '…')}” Meaning, context, other translations and cross-references."
    else
      "Read #{reference} in the KJV, WEB and BSB, with its context, cross-references and what people are saying about it."
    end
  end

  def scripture_translation_name(code)
    ScriptureVerse::TRANSLATIONS.dig(code, :name) || code.upcase
  end

  def scripture_translation_short(code)
    ScriptureVerse::TRANSLATIONS.dig(code, :short) || code.upcase
  end

  # Paragraphs of stored insight text (plain text, blank-line separated).
  def scripture_paragraphs(text)
    safe_join(text.to_s.split(/\n{2,}/).map(&:strip).compact_blank.map { |para| tag.p(para) })
  end

  def scripture_breadcrumbs(reference)
    crumbs = [ [ "Bible", scripture_index_url ], [ reference.book.name, scripture_index_url(anchor: reference.book.slug) ] ]
    if reference.chapter?
      crumbs << [ reference.to_s, scripture_page_url(reference.slug) ]
    else
      chapter = reference.chapter_reference
      crumbs << [ chapter.to_s, scripture_page_url(chapter.slug) ]
      crumbs << [ reference.to_s, scripture_page_url(reference.slug) ]
    end
    crumbs
  end

  def scripture_structured_data(reference, insight)
    crumbs = scripture_breadcrumbs(reference)
    graph = [ {
      "@type" => "BreadcrumbList",
      "itemListElement" => crumbs.each_with_index.map do |(name, url), i|
        { "@type" => "ListItem", "position" => i + 1, "name" => name, "item" => url }
      end
    } ]
    if insight
      graph << {
        "@type" => "FAQPage",
        "mainEntity" => [
          [ "What does #{reference.plain} mean?", insight.explanation ],
          [ "What is the context of #{reference.plain}?", insight.context ]
        ].map do |question, answer|
          { "@type" => "Question", "name" => question,
            "acceptedAnswer" => { "@type" => "Answer", "text" => answer.squish } }
        end
      }
    end
    tag.script(json_escape({ "@context" => "https://schema.org", "@graph" => graph }.to_json).html_safe,
               type: "application/ld+json")
  end

  # Short preview of a breath for the "what people are saying" list.
  def scripture_post_excerpt(post, length: 180)
    post.content.to_plain_text.to_s.squish.truncate(length, separator: " ")
  end
end
