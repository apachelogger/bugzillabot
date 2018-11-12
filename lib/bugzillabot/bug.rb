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

require 'time'

require_relative 'connection'

module Bugzillabot
  # Bug object
  # Describes a bug.
  # @see https://bugzilla.readthedocs.io/en/5.0/api/core/v1/bug.html
  class Bug < OpenStruct
    # History object
    # Describes an event in the history of the bug. One event may be comprised
    # of multiple changes.
    # @see https://bugzilla.readthedocs.io/en/5.0/api/core/v1/bug.html#bug-history
    class HistoryEvent < OpenStruct
      def initialize(data)
        super(data)
        self.changes = changes.collect { |x| Change.new(x) }
        self.when = Time.parse(self.when)
      end

      # Change object
      # A change occured in a HistoryEvent to mutate a field of the bug.
      # @see https://bugzilla.readthedocs.io/en/5.0/api/core/v1/bug.html#bug-history
      class Change < OpenStruct
        def status?
          field_name == 'status'
        end
      end
    end

    # Comment object
    # Comments appear on bugs.
    # @see https://bugzilla.readthedocs.io/en/5.0/api/core/v1/comment.html#get-comments
    class Comment < OpenStruct
      def initialize(data)
        super(data)
        self.creation_time = Time.parse(creation_time)
        # time is overridden and not accessible see #time
      end

      # @deprecated
      def time
        creation_time # time is only for compat and may get deprecated
      end
    end

    # @return [Time, nil] time at which this bug changed its 'status' field
    #    last.
    # @note cached
    def changed_status_at
      @changed_status_at ||= history.reverse.find do |event|
        next unless event.changes.any?(&:status?)
        true
      end.when
    end

    # @return [Time, nil] time at which the most recent comment was created.
    def last_comment_at
      return comments[-1].creation_time if comments[-1]
      nil
    end

    # @param new_since [Time] restricts query to newer than the specified time
    # @return [Array<Comment>] comments of this bug
    # @see https://bugzilla.readthedocs.io/en/5.0/api/core/v1/comment.html#get-comments
    # @note cached (unless new_since is used)
    def comments(new_since: nil)
      return comments_query(new_since: new_since.iso8601) if new_since
      self['comments'] ||= comments_query # query all and cache the result
    end

    # @return [Array<HistoryEvent>] complete history of this bug
    def history
      self['history'] ||= begin
        res = @connection.get("bug/#{id}/history")
        data = JSON.parse(res.body)
        history = data.fetch('bugs')[0]['history']
        history.collect { |x| HistoryEvent.new(x) }
      end
    end

    # Convenience wrapper around #changed_status_at and #comments to fetch the
    # subset of comments since the status changed last.
    # @return [Array<Comment>] comments of this bug since it #changed_status_at
    # @note cached
    def comments_since_status_change
      raise if changed_status_at.nil?
      @comments_since_status_change ||= comments(new_since: changed_status_at)
    end

    # Takes any arguments of update-bug API.
    # @note this does not update the bug object(s). To get the update you need
    #   to #get new Bug instances.
    # FIXME: maybe implement in-place update of the bug objects.
    # https://bugzilla.readthedocs.io/en/5.0/api/core/v1/bug.html#update-bug
    def update(**kwords)
      @connection.put("bug/#{id}") do |req|
        req.body = JSON.generate(kwords)
      end
    end

    # Creates a new comment on the bug.
    # @param body String the acutal comment
    # @param kwords Hash any arguments supported by the actual API endpoint
    # @note This does not update the object. You need to #get a new instance.
    # https://bugzilla.readthedocs.io/en/5.0/api/core/v1/comment.html#rest-add-comment
    def comment(body, **kwords)
      @connection.post("bug/#{id}/comment") do |req|
        object = { comment: body }.merge(kwords)
        req.body = JSON.generate(object)
      end
    end

    class << self
      # FIXME: docs also suggest searching with id list, should be supported
      #   somewhere
      # https://bugzilla.readthedocs.io/en/5.0/api/core/v1/bug.html#get-bug
      def get(id_or_alias, connection = Connection.new)
        res = connection.get("bug/#{id_or_alias}")
        from_s(res.body, connection)[0]
      end

      # A search gets automatically paginated iff this method is called with
      # a block and without explicit `offset` and `limit` parameters.
      #
      # When any of these is not true a blanket search is done. This search
      # will still yield but not automatically paginate the request (i.e.
      # if you do a heavy search it will take a long time to return).
      #
      # @return <[Bug], nil> Blanket searches always return the full result
      #   array, even when used with a block. Automatically paginated searches
      #   never return an array but always return nil. As such pagination
      #   is always lighter on the memory footprint.
      def search(kwords, connection = Connection.new, &block)
        unless %i[offset limit].any? { |x| kwords.include?(x) } && block_given?
          yield_pages(kwords, connection, &block)
          return nil
        end
        search_all(kwords, connection)
      end

      private

      def yield_pages(kwords, connection = Connection.new, &block)
        # There is no one right value. 8 is sufficiently small not to break
        # the remote, but large enough to not have to query too much.
        limit = kwords.fetch('limit', 8)
        offset = 0
        loop do
          args = kwords.merge(limit: limit, offset: offset)
          # search_all yields when given a block
          bugs = search_all(args, connection, &block)
          offset += limit
          break if bugs.empty?
        end
      end

      def search_all(kwords, connection = Connection.new, &block)
        res = connection.get('bug') do |req|
          req.params.merge!(kwords)
        end
        bugs = from_s(res.body, connection)
        # FIXME: this is simply a caching measure to have the entire object
        #   resolved immediately so the debug output is easier to read. should
        #   be dropped in favor of lazyness
        bugs.collect do |bug|
          bug.history
          bug.comments_since_status_change
          yield bug if block_given?
          bug
        end
      end

      def from_s(string, connection)
        bugs = JSON.parse(string).fetch('bugs')
        bugs.collect { |x| Bug.new(x, connection) }
      end
    end

    private

    def initialize(data, connection = Connection.new)
      @connection = connection
      super(data)
    end

    def comments_query(**kwords)
      res = @connection.get("bug/#{id}/comment") do |req|
        req.params = req.params.merge(kwords)
      end
      data = JSON.parse(res.body)
      comments = data.fetch('bugs').fetch(id.to_s).fetch('comments')
      comments.collect { |x| Comment.new(x) }
    end
  end
end
