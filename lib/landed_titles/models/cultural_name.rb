# frozen_string_literal: true

module LandedTitles
  class CulturalName < ActiveRecord::Base
    belongs_to :title

    validates :value,
              presence: true,
              allow_blank: false

    validates :name_list,
              presence: true,
              allow_blank: false,
              uniqueness: { scope: %i[title source] }

    validates :source,
              presence: true,
              allow_blank: false
  end
end
