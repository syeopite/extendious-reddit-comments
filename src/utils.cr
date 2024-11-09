module RedditCommentsExt
  def self.fill_links(html, scheme, host)
    # Check if the document is empty
    # Prevents edge-case bug with Reddit comments, see issue #3115
    if html.nil? || html.empty?
      return html
    end

    html = XML.parse_html(html)

    html.xpath_nodes("//a").each do |match|
      url = URI.parse(match["href"])
      # Reddit links don't have host
      if !url.host && !match["href"].starts_with?("javascript") && !url.to_s.ends_with? "#"
        url.scheme = scheme
        url.host = host
        match["href"] = url
      end
    end

    return html.to_xml(options: XML::SaveOptions::NO_DECL)
  end
end
