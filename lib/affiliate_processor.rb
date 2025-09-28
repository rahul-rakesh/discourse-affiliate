# frozen_string_literal: true

class AffiliateProcessor
  AMAZON_SHORT_DOMAINS = %w[amzn.to amzn.com amzn.eu amzn.in a.co].freeze

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
    begin
      # Follow redirects to get the final Amazon URL
      response = Excon.head(url, expects: [200, 301, 302, 303, 307, 308], middlewares: Excon.defaults[:middlewares] + [Excon::Middleware::RedirectFollower])
      final_url = response.headers['Location'] || url

      # Parse the final URL to extract the product ID and create a clean URL
      final_uri = URI.parse(final_url)
      if final_uri.host&.include?('amazon.')
        # Extract ASIN/product ID from path
        if match = final_uri.path.match(%r{/dp/([A-Z0-9]{10})|/gp/product/([A-Z0-9]{10})})
          asin = match[1] || match[2]
          # Create clean Amazon URL based on the domain
          domain_mapping = {
            'amazon.in' => 'in',
            'amazon.com' => 'com',
            'amazon.co.uk' => 'co_uk',
            'amazon.de' => 'de',
            'amazon.fr' => 'fr',
            'amazon.co.jp' => 'co_jp',
            'amazon.ca' => 'ca',
            'amazon.com.au' => 'com_au',
            'amazon.com.br' => 'com_br',
            'amazon.com.mx' => 'com_mx',
            'amazon.es' => 'es',
            'amazon.it' => 'it',
            'amazon.nl' => 'nl'
          }

          domain_key = domain_mapping[final_uri.host] || 'com'
          return "https://#{final_uri.host}/dp/#{asin}"
        end
      end

      final_url
    rescue => e
      Rails.logger.warn "Failed to expand Amazon short link #{url}: #{e.message}"
      url
    end
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
