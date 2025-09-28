# frozen_string_literal: true

# name: discourse-affiliate
# about: Allows the creation of Amazon affiliate links on your forum.
# meta_topic_id: 101937
# version: 0.2
# authors: Régis Hanol (zogstrip), Sam Saffron
# url: https://github.com/discourse/discourse-affiliate

enabled_site_setting :affiliate_enabled

after_initialize do
  require File.expand_path(File.dirname(__FILE__) + "/lib/affiliate_processor")

  # Process links during normal post creation/editing
  on(:post_process_cooked) do |doc, post|
    process_affiliate_links(doc)
    true
  end

  # Also process links during rebake
  on(:before_post_process_cooked) do |doc, post|
    process_affiliate_links(doc)
    true
  end

  def process_affiliate_links(doc)
    doc.css("a[href]").each do |a|
      original_href = a["href"]
      new_href = AffiliateProcessor.apply(original_href)

      # Only update if the URL actually changed
      if new_href != original_href
        a["href"] = new_href
      end
    end
  end
end
