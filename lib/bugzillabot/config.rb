# Copyright (C) 2018 Harald Sitter <sitter@kde.org>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) version 3, or any
# later version accepted by the membership of KDE e.V. (or its
# successor approved by the membership of KDE e.V.), which shall
# act as a proxy defined in Section 6 of version 3 of the license.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library.  If not, see <http://www.gnu.org/licenses/>.

require 'yaml'

module Bugzillabot
  # Configuration wrapper
  class Config
    class << self
      # Order matters for these.
      DEFAULT_LOAD_PATHS = [
        File.absolute_path(File.join(__dir__, '../../.config.yaml')),
        File.join(Dir.home, '.config/bugzillabot.yaml')
      ].freeze

      def load_paths
        @load_paths ||= DEFAULT_LOAD_PATHS
      end

      attr_writer :load_paths
    end

    attr_reader :path
    attr_reader :url
    attr_reader :api_key

    def initialize
      path = self.class.load_paths.find { |x| File.exist?(x) }
      unless path
        raise "Failed to find a config file in #{local_path} nor #{user_path}"
      end
      load(path)
    end

    def load(path)
      warn "Loading #{path}"
      @path = path
      type = ENV['PRODUCTION'] ? 'production' : 'testing'
      @data = YAML.load_file(path).fetch(type)
      @url = @data.fetch('url')
      @api_key = @data.fetch('api_key')
    end

    def bugzilla_url
      url.gsub('/rest', '')
    end
  end
end
