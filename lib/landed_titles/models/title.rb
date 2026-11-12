# frozen_string_literal: true

module LandedTitles
  class Title < ActiveRecord::Base
    has_many :cultural_names

    validates :name,
              presence: true,
              allow_blank: false,
              uniqueness: true

    attribute :offset, default: ''
  end
end
