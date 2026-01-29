# frozen_string_literal: true

module TimelogBot
  module Models
    class Project < Sequel::Model(DB[:projects])
      one_to_many :time_entries

      def self.all_names
        select_map(:name)
      end

      def self.find_by_name(name)
        first(Sequel.ilike(:name, name))
      end

      def self.find_or_create_by_name(name)
        find_by_name(name) || create(name: name.strip)
      end
    end
  end
end
