# frozen_string_literal: true

class AffiliateProcessor
  AMAZON_SHORT_DOMAINS = %w[amzn.to amzn.com amzn.eu amzn.in a.co].freeze
  ASIN_PATH = %r{/(?:dp|gp/product)/([A-Z0-9]{10})(?=/|\z)}
  SHORT_LINK_REDIRECT_STATUSES = [301, 302, 303, 307, 308].freeze
  SHORT_LINK_MAX_HOPS = 3
  SHORT_LINK_TIMEOUT = 5
  SHORT_LINK_SUCCESS_TTL = 30.days
  SHORT_LINK_FAILURE_TTL = 1.hour

  def self.create_amazon_rule(domain)
    lambda do |url, uri|
      code = SiteSetting.get("affiliate_amazon_#{domain.gsub(".", "_")}")
      if code.present?
        original_query_array = URI.decode_www_form(String(uri.query)).to_h
        query_array = [["tag", code]]
        query_array << ["k", original_query_array["k"]] if original_query_array["k"].present?
        if original_query_array["ref"].present? && original_query_array["k"].present?
          query_array << ["ref", original_query_array["ref"]]
        end
        if original_query_array["node"].present?
          query_array << ["node", original_query_array["node"]]
        end
        uri.query = URI.encode_www_form(query_array)
        uri.to_s
      else
        url
      end
    end
  end

  def self.expand_amazon_short_link(url)
    cache_key = "discourse-affiliate:amazon-short-link:#{Digest::SHA1.hexdigest(url)}"
    cached = Discourse.cache.read(cache_key)
    return cached if cached

    expanded = resolve_amazon_short_link(url)
    expires_in = expanded == url ? SHORT_LINK_FAILURE_TTL : SHORT_LINK_SUCCESS_TTL
    Discourse.cache.write(cache_key, expanded, expires_in:)
    expanded
  end

  def self.resolve_amazon_short_link(url)
    current = url

    SHORT_LINK_MAX_HOPS.times do
      # The short-link hosts answer HEAD with 404, so the redirect is read from a GET.
      response =
        Excon.get(
          current,
          connect_timeout: SHORT_LINK_TIMEOUT,
          read_timeout: SHORT_LINK_TIMEOUT,
          write_timeout: SHORT_LINK_TIMEOUT,
        )
      location = response.headers["Location"]
      return url if SHORT_LINK_REDIRECT_STATUSES.exclude?(response.status) || location.blank?

      target = URI.join(current, location)
      return amazon_store_url(target) || url if AMAZON_SHORT_DOMAINS.exclude?(target.host)

      current = target.to_s
    end

    url
  rescue StandardError => e
    Rails.logger.warn "Failed to expand Amazon short link #{url}: #{e.message}"
    url
  end

  def self.amazon_store_url(uri)
    return if !rules.key?(uri.host)

    asin = uri.path[ASIN_PATH, 1]
    return "https://#{uri.host}/dp/#{asin}" if asin

    # A dead short link lands on the store's front page.
    uri.to_s if uri.path.present? && uri.path != "/"
  end

  def self.rules
    return @rules if @rules
    postfixes = %w[com com.au com.br com.mx ca cn co.jp co.uk de es fr in it nl to co eu]

    rules = {}

    postfixes.map do |postfix|
      rule = create_amazon_rule(postfix)

      rules["amzn.com"] = rule if postfix == "com"
      rules["amzn.to"] = create_amazon_rule("com") if postfix == "to"
      rules["amzn.eu"] = rule if postfix == "eu"
      rules["amzn.in"] = create_amazon_rule("in") if postfix == "in"
      rules["a.co"] = create_amazon_rule("com") if postfix == "co"
      rules["www.amazon.#{postfix}"] = rule
      rules["smile.amazon.#{postfix}"] = rule
      rules["amazon.#{postfix}"] = rule
    end

    rule =
      lambda do |url, uri|
        code = SiteSetting.affiliate_ldlc_com
        if code.present?
          uri.fragment = code
          uri.to_s
        else
          url
        end
      end

    rules["www.ldlc.com"] = rule
    rules["ldlc.com"] = rule

    @rules = rules
  end

  def self.apply(url)
    uri = URI.parse(url)

    if uri.scheme == "http" || uri.scheme == "https"
      # Check if this is an Amazon short link and expand it first
      if AMAZON_SHORT_DOMAINS.include?(uri.host)
        expanded_url = expand_amazon_short_link(url)
        return apply(expanded_url) if expanded_url != url
      end

      rule = rules[uri.host]
      return rule.call(url, uri) if rule
    end

    url
  rescue StandardError => e
    Rails.logger.warn "Failed to process affiliate URL #{url}: #{e.message}"
    url
  end
end
