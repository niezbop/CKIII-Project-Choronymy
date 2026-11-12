# frozen_string_literal: true

require 'active_record'

module LandedTitles
  module Persistence
    def self.setup(persist_to: ':memory:')
      create_database(persist_to:)
      define_tables
    end

    def self.create_database(persist_to: ':memory:')
      ActiveRecord::Base.logger = Logger.new(STDERR)
      ActiveRecord::Base.logger.level = 1

      ActiveRecord::Base.establish_connection(
        adapter: 'sqlite3',
        database: persist_to
      )
    end

    def self.define_tables
      ActiveRecord::Schema.define do
        create_table :titles, force: :cascade do |table|
          table.string :name, default: '', null: false

          table.index [:name], name: 'index_titles_on_name_uniqueness', unique: true
        end

        create_table :cultural_names, force: :cascade do |table|
          table.references :title, index: true
          table.string :value, default: '', null: false
          table.string :name_list, default: '', null: false
          table.string :comment, default: '', null: true
          table.string :source, default: '', null: false

          table.index %i[title_id name_list source], name: 'index_names_on_uniqueness_in_source', unique: true
        end
      end
    end

    def self.empty?
      !ActiveRecord::Base.connection.tables.any?
    end
  end
end
