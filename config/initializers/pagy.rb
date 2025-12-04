# frozen_string_literal: true

require 'pagy/extras/overflow'
require 'pagy/extras/navs'

Pagy::DEFAULT[:items] = 15
Pagy::DEFAULT[:overflow] = :last_page

