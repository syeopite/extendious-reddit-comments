require "http"
require "xml"
require "json"

require "inv-ext-utils"

require "./reddit.cr"
require "./utils.cr"


# A Invidious Extension to show comments from Reddit
module RedditCommentsExt
  extend InvExtUtils::Extension

  def self.load()
    RedditCommentsExt::Routing.add_routes()
  end

  module Routing
    include InvExtUtils::Routing

    def self.add_routes
      extinv_before_get "/api/v1/comments/:id", Routing, :before_comments_api
    end

    def self.before_comments_api(env)
      id = env.params.url["id"]
      source = env.params.query["source"]? || "youtube"
      format = env.params.query["format"]? || "json"

      return if source != "reddit"

      env.response.content_type = "application/json"

      sort_by = env.params.query["sort_by"]?.try &.downcase || "confidence"

      begin
        comments, reddit_thread = RedditCommentsExt.fetch_reddit(id, sort_by: sort_by)
      rescue ex
        comments = nil
        reddit_thread = nil
      end

      if !reddit_thread || !comments
        haltf env, 404, error_json(404, "No reddit threads found")
      end

      if format == "json"
        reddit_thread = JSON.parse(reddit_thread.to_json).as_h
        reddit_thread["comments"] = JSON.parse(comments.to_json)

        haltf env, 200, reddit_thread.to_json
      else
        content_html = RedditCommentsExt.template_reddit(comments)
        content_html = RedditCommentsExt.fill_links(content_html, "https", "www.reddit.com")
        response = {
          "title"       => reddit_thread.title,
          "permalink"   => reddit_thread.permalink,
          "contentHtml" => content_html,
        }

        haltf env, 200, response.to_json
      end
    end
  end
end
