# frozen_string_literal: true

require "test_helper"

class CleanLanguageTest < ActiveSupport::TestCase
  test "catches offensive words, including disguised spellings" do
    [ "you f*cking idiot", "sh1t", "fuuuuck", "f u c k off", "$hit", "b!tch", "motherfucker", "bullshit",
      "you ashawo", "send nudes", "BITCHES", "n1gga", "c u n t" ].each do |text|
      assert CleanLanguage.offensive?(text), "should block: #{text}"
    end
  end

  test "allows Nigeria, Bible words and everyday words" do
    [ "I am from Nigeria, a proud Nigerian", "Niger river", "The cock crowed", "Balaam and his ass",
      "Rahab the harlot", "a bastard shall not enter", "go to hell", "God freed me from porn addiction",
      "class assessment", "Fukushima", "shiitake", "Scunthorpe", "Dickens", "cucumber", "Titus 2:3",
      "made of shittim wood", "the Girgashites", "Abel-shittim", "the Elkoshite" ].each do |text|
      assert_not CleanLanguage.offensive?(text), "should allow: #{text}"
    end
  end

  test "insults aimed at someone are blocked" do
    [ "you are mad", "you madman", "You idiot!", "youre stupid", "u r a mumu", "you are a big fool",
      "stupid man", "useless girl", "Shut up!", "shut your mouth", "you dog", "you are such a moron" ].each do |text|
      assert CleanLanguage.offensive?(text), "should block: #{text}"
    end
  end

  test "the same words are fine when not aimed at anyone, or in scripture" do
    [ "you are not useless, God loves you", "I was a fool before Christ", "Ye fools and blind",
      "Thou fool, this night thy soul", "you are mad blessed this year", "Are you mad at God? Tell Him",
      "That stupid habit nearly ruined me", "the priest shall shut up the house", "O foolish people and unwise",
      "a dumb man possessed", "one of you is a devil", "Have I need of mad men" ].each do |text|
      assert_not CleanLanguage.offensive?(text), "should allow: #{text}"
    end
  end

  test "coded sexual talk is blocked" do
    [ "your kitty is dripping", "Ur kitty is so wet", "your body is so sexy", "I want to taste you",
      "lemme lick u", "send me bedroom pics", "sit on my face", "im wet for you", "🍆💦" ].each do |text|
      assert CleanLanguage.offensive?(text), "should block: #{text}"
    end
  end

  test "everyday and Bible words used innocently are fine" do
    [ "your body is a temple of the Holy Spirit", "taste and see that the Lord is good",
      "my kitty is sick, pray for her", "send me the pictures from church", "I want to eat with you after service",
      "your thing is ready, come pick it up", "🍑 peach season!", "is there any thing too hard for me?" ].each do |text|
      assert_not CleanLanguage.offensive?(text), "should allow: #{text}"
    end
  end
end
