module RedditCommentsExt
  class RedditThing
    include JSON::Serializable

    property kind : String
    property data : RedditComment | RedditLink | RedditMore | RedditListing
  end

  class RedditComment
    include JSON::Serializable

    property author : String
    property body_html : String
    property replies : RedditThing | String
    property score : Int32
    property depth : Int32
    property permalink : String

    @[JSON::Field(converter: RedditCommentsExt::RedditComment::TimeConverter)]
    property created_utc : Time

    module TimeConverter
      def self.from_json(value : JSON::PullParser) : Time
        Time.unix(value.read_float.to_i)
      end

      def self.to_json(value : Time, json : JSON::Builder)
        json.number(value.to_unix)
      end
    end
  end

  struct RedditLink
    include JSON::Serializable

    property author : String
    property score : Int32
    property subreddit : String
    property num_comments : Int32
    property id : String
    property permalink : String
    property title : String
  end

  struct RedditMore
    include JSON::Serializable

    property children : Array(String)
    property count : Int32
    property depth : Int32
  end

  class RedditListing
    include JSON::Serializable

    property children : Array(RedditThing)
    property modhash : String
  end

  def self.fetch_reddit(id, sort_by = "confidence")
    client = HTTP::Client.new(URI.parse("https://www.reddit.com"))
    headers = HTTP::Headers{"User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/115.0"}

    # TODO: Use something like #479 for a static list of instances to use here
    query = URI::Params.encode({q: "(url:3D#{id} OR url:#{id}) AND (site:invidio.us OR site:youtube.com OR site:youtu.be)"})
    search_results = client.get("/search.json?#{query}", headers)

    if search_results.status_code == 200
      search_results = RedditThing.from_json(search_results.body)

      # For videos that have more than one thread, choose the one with the highest score
      threads = search_results.data.as(RedditListing).children
      thread = threads.max_by?(&.data.as(RedditLink).score).try(&.data.as(RedditLink))
      result = thread.try do |t|
        body = client.get("/r/#{t.subreddit}/comments/#{t.id}.json?limit=100&sort=#{sort_by}", headers).body
        Array(RedditThing).from_json(body)
      end
      result ||= [] of RedditThing
    elsif search_results.status_code == 302
      # Previously, if there was only one result then the API would redirect to that result.
      # Now, it appears it will still return a listing so this section is likely unnecessary.

      result = client.get(search_results.headers["Location"], headers).body
      result = Array(RedditThing).from_json(result)

      thread = result[0].data.as(RedditListing).children[0].data.as(RedditLink)
    else
      print(search_results.status_code)
      raise IO::Error.new("Comments not found.")
    end

    client.close

    comments = result[1]?.try(&.data.as(RedditListing).children)
    comments ||= [] of RedditThing
    return comments, thread
  end

  def self.template_reddit(root)
    String.build do |html|
      root.each do |child|
        if child.data.is_a?(RedditComment)
          child = child.data.as(RedditComment)
          body_html = HTML.unescape(child.body_html)

          replies_html = ""
          if child.replies.is_a?(RedditThing)
            replies = child.replies.as(RedditThing)
            replies_html = self.template_reddit(replies.data.as(RedditListing).children)
          end

          if child.depth > 0
            html << <<-END_HTML
            <div class="pure-g">
            <div class="pure-u-1-24">
            </div>
            <div class="pure-u-23-24">
            END_HTML
          else
            html << <<-END_HTML
            <div class="pure-g">
            <div class="pure-u-1">
            END_HTML
          end

          html << <<-END_HTML
          <p>
            <a href="javascript:void(0)" data-onclick="toggle_parent">[ − ]</a>
            <b><a href="https://www.reddit.com/user/#{child.author}">#{child.author}</a></b>
            #{child.score}
            <span title="#{child.created_utc.to_s("%a %B %-d %T %Y UTC")}">#{child.created_utc.to_s("%a %B %-d %T %Y UTC")}</span>
            <a href="https://www.reddit.com#{child.permalink}" title="permalink">permalink</a>
            </p>
            <div>
            #{body_html}
            #{replies_html}
          </div>
          </div>
          </div>
          END_HTML
        end
      end
    end
  end
end
