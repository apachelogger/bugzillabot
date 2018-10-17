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

require 'delegate'
require 'faraday'
require 'json'
require 'logger'
require 'uri'

module Bugzillabot
  # Connection adaptor.
  # This class wraps HTTP interactions for our purposes and adds general purpose
  # automation on top of the raw HTTP actions.
  class Connection < DelegateClass(Faraday::Connection)
    def initialize(url: Bugzillabot.config.url,
                   api_key: Bugzillabot.config.api_key)
      # params: { 'Bugzilla_api_key' => api_key }
      # headers: { 'X-BUGZILLA-API-KEY' => api_key }
      # FIXME: should query the version and use the headers on 6.0 and the
      #   params on 5.0
      @connection = Faraday.new(url: url,
                                params: { 'Bugzilla_api_key' => api_key },
                                headers: default_headers) do |c|
        c.request(:url_encoded)
        c.adapter Faraday.default_adapter # make requests with Net::HTTP
      end
      enable_logging if ENV['DEBUG']

      super(@connection)
    end

    private

    def default_headers
      { 'Accept' => 'application/json',
        'Content-Type' => 'application/json' }
    end

    def enable_logging
      @connection.response(:logger,
                           Logger.new(STDOUT),
                           bodies: true) do |logger|
        logger.filter(/(Bugzilla_api_key=)(\w+)/, '\1[REMOVED]')
        logger.filter(/(X-BUGZILLA-API-KEY:) "(\w+)"/, '\1[REMOVED]')
      end
    end
  end
end
