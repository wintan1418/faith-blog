# frozen_string_literal: true

module Ai
  module Composer
    # Answers for the composer's "Suggest scripture" and "Check tone" buttons
    # when the AI is busy or unreachable, so the buttons never just fail.
    # Simple, local and instant: themes matched by keyword, and the word filter.
    module Fallback
      Verse = ScriptureSuggester::Verse

      THEMES = [
        [ /\b(?:anxi\w*|worr\w*|stress\w*|afraid|fear\w*|scared|panic\w*)\b/, [
          [ "Philippians 4:6-7", "Bring every worry to God in prayer; His peace will guard your heart." ],
          [ "1 Peter 5:7", "Cast your cares on Him, because He cares for you." ],
          [ "Isaiah 41:10", "Do not fear: God is with you and will strengthen you." ]
        ] ],
        [ /\b(?:grie\w*|mourn\w*|loss|lost|died|death|funeral|pass(?:ed)?\s+away|broken\s*hearted|heartbr\w*)\b/, [
          [ "Psalm 34:18", "The Lord is near to the brokenhearted." ],
          [ "Matthew 5:4", "Those who mourn shall be comforted." ],
          [ "Revelation 21:4", "God will wipe away every tear." ]
        ] ],
        [ /\b(?:thank\w*|grateful|gratitude|testimon\w*|praise|bless(?:ed|ing)?)\b/, [
          [ "1 Thessalonians 5:18", "Give thanks in every circumstance." ],
          [ "Psalm 107:1", "Give thanks to the Lord, for He is good." ],
          [ "Psalm 103:2", "Bless the Lord and forget not His benefits." ]
        ] ],
        [ /\b(?:sin\w*|forgiv\w*|repent\w*|guilt\w*|shame\w*|mistake\w*)\b/, [
          [ "1 John 1:9", "If we confess our sins, He is faithful to forgive." ],
          [ "Psalm 51:10", "A prayer for a clean heart and a right spirit." ],
          [ "Romans 8:1", "There is no condemnation for those in Christ Jesus." ]
        ] ],
        [ /\b(?:sick\w*|ill|illness|heal\w*|hospital|pain|disease)\b/, [
          [ "James 5:15", "The prayer of faith shall save the sick." ],
          [ "Jeremiah 17:14", "Heal me, O Lord, and I shall be healed." ],
          [ "Isaiah 53:5", "By His stripes we are healed." ]
        ] ],
        [ /\b(?:money|job|work|bills?|rent|provision|provide|financ\w*|broke|business)\b/, [
          [ "Philippians 4:19", "God will supply all your need." ],
          [ "Matthew 6:33", "Seek first the kingdom, and these things will be added." ],
          [ "Proverbs 3:5-6", "Trust the Lord with all your heart; He will direct your paths." ]
        ] ],
        [ /\b(?:wait\w*|patien\w*|delay\w*|when\s+will)\b/, [
          [ "Isaiah 40:31", "Those who wait on the Lord renew their strength." ],
          [ "Psalm 27:14", "Wait on the Lord and be of good courage." ],
          [ "Lamentations 3:25", "The Lord is good to those who wait for Him." ]
        ] ],
        [ /\b(?:decid\w*|decision|direction|guid\w*|confus\w*|which\s+way|path)\b/, [
          [ "Proverbs 3:5-6", "Trust Him and He will direct your paths." ],
          [ "James 1:5", "Ask God for wisdom; He gives it generously." ],
          [ "Psalm 32:8", "God will instruct you and teach you the way to go." ]
        ] ],
        [ /\b(?:weak\w*|tired|weary|exhaust\w*|strength|give\s+up|burn(?:ed|t)?\s*out)\b/, [
          [ "2 Corinthians 12:9", "His strength is made perfect in weakness." ],
          [ "Matthew 11:28", "Come to Him, all who are weary, and find rest." ],
          [ "Isaiah 40:29", "He gives power to the faint." ]
        ] ],
        [ /\b(?:doubt\w*|faith|believ\w*|trust\w*)\b/, [
          [ "Hebrews 11:1", "Faith is the substance of things hoped for." ],
          [ "Mark 9:24", "Lord, I believe; help my unbelief." ],
          [ "Romans 10:17", "Faith comes by hearing the word of God." ]
        ] ],
        [ /\b(?:lonel\w*|alone|rejected|forsaken|abandon\w*)\b/, [
          [ "Deuteronomy 31:6", "He will never leave you nor forsake you." ],
          [ "Psalm 27:10", "When others forsake you, the Lord takes you up." ],
          [ "Matthew 28:20", "I am with you always." ]
        ] ],
        [ /\b(?:angr\w*|anger|bitter\w*|offend\w*|hurt\s+me|enem\w*)\b/, [
          [ "Ephesians 4:26", "Be angry and sin not; don't let the sun go down on your wrath." ],
          [ "Ephesians 4:32", "Be kind and forgiving, as God forgave you." ],
          [ "Romans 12:21", "Overcome evil with good." ]
        ] ],
        [ /\b(?:marri\w*|husband|wife|famil\w*|child\w*|kids?|parent\w*)\b/, [
          [ "Joshua 24:15", "As for me and my house, we will serve the Lord." ],
          [ "1 Corinthians 13:4-7", "Love is patient and kind." ],
          [ "Proverbs 22:6", "Train up a child in the way he should go." ]
        ] ],
        [ /\b(?:prophe\w*|holy\s+spirit|spirit|anoint\w*|gifts?)\b/, [
          [ "Numbers 11:29", "Would God that all the Lord's people were prophets." ],
          [ "Joel 2:28", "I will pour out my Spirit upon all flesh." ],
          [ "1 Corinthians 14:1", "Desire spiritual gifts, especially to prophesy." ]
        ] ],
        [ /\b(?:pray\w*|intercede\w*)\b/, [
          [ "Matthew 7:7", "Ask, seek and knock; it shall be given you." ],
          [ "James 5:16", "The fervent prayer of a righteous man avails much." ],
          [ "1 Thessalonians 5:17", "Pray without ceasing." ]
        ] ]
      ].freeze

      GENERAL = [
        [ "Romans 8:28", "All things work together for good to those who love God." ],
        [ "Psalm 46:1", "God is our refuge and strength, a very present help." ],
        [ "Jeremiah 29:11", "God's thoughts toward you are of peace and hope." ]
      ].freeze

      module_function

      # Up to 3 verses for the draft's strongest themes.
      def scripture(text)
        words = text.to_s.downcase
        picks = THEMES.select { |pattern, _| words.match?(pattern) }
                      .sort_by { |pattern, _| -words.scan(pattern).size }
                      .flat_map { |_, verses| verses }
        picks = GENERAL if picks.empty?
        picks.uniq(&:first).first(3).map { |ref, reason| Verse.new(reference: ref, reason: reason) }
      end

      # A quick tone read from the word filter.
      def tone(text)
        if CleanLanguage.offensive?(text)
          GentlenessCheck::Result.new(
            tone: "harsh", confidence: 0.6,
            summary: "Some words here could hurt someone.",
            nudge: "Consider rephrasing the harsh part so it lands in love.",
            suggestion: ""
          )
        else
          GentlenessCheck::Result.new(
            tone: "gentle", confidence: 0.5,
            summary: "Nothing harsh stood out in a quick check.",
            nudge: "", suggestion: ""
          )
        end
      end
    end
  end
end
