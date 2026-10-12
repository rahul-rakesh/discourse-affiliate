# frozen_string_literal: true

describe AffiliateProcessor do
  def r(url)
    AffiliateProcessor.apply(url)
  end

  before { enable_current_plugin }

  it "can apply affiliate code to ldlc" do
    SiteSetting.affiliate_ldlc_com = "samsshop"

    expect(r("http://www.ldlc.com/some_product?xyz=1")).to eq(
      "http://www.ldlc.com/some_product?xyz=1#samsshop",
    )
    expect(r("https://ldlc.com/some_product?xyz=1")).to eq(
      "https://ldlc.com/some_product?xyz=1#samsshop",
    )
  end

  it "can apply affiliate code correctly to amazon" do
    SiteSetting.affiliate_amazon_com = "sams-shop"
    SiteSetting.affiliate_amazon_ca = "ca-sams-shop"
    SiteSetting.affiliate_amazon_com_au = "au-sams-shop"
    SiteSetting.affiliate_amazon_eu = "eu-sams-shop"
    SiteSetting.affiliate_amazon_in = "in-sams-shop"

    expect(r("https://www.amazon.com")).to eq("https://www.amazon.com?tag=sams-shop")
    expect(r("http://www.amazon.com/some_product?xyz=1")).to eq(
      "http://www.amazon.com/some_product?tag=sams-shop",
    )
    expect(r("https://www.amazon.com/some_product?xyz=1")).to eq(
      "https://www.amazon.com/some_product?tag=sams-shop",
    )
    expect(r("https://www.amazon.com?hello=1&tag=bobs-shop")).to eq(
      "https://www.amazon.com?tag=sams-shop",
    )
    expect(r("https://smile.amazon.com/some_product?xyz=1")).to eq(
      "https://smile.amazon.com/some_product?tag=sams-shop",
    )
    expect(r("https://www.amazon.com.au/some_product?xyz=1")).to eq(
      "https://www.amazon.com.au/some_product?tag=au-sams-shop",
    )
    expect(
      r(
        "https://www.amazon.ca/Dragon-Quest-Echoes-Elusive-Age-PlayStation/dp/B07BP3J6RG/ref=br_asw_pdt-5?pf_rd_m=ATVPDKIKX0DER&pf_rd_s=&pf_rd_r=XFGPRSG0SVD5K3RKX5T3&pf_rd_t=36701&pf_rd_p=f8585743-c043-4665-80a7-0cc5fe97d596&pf_rd_i=desktop&th=1",
      ),
    ).to eq(
      "https://www.amazon.ca/Dragon-Quest-Echoes-Elusive-Age-PlayStation/dp/B07BP3J6RG/ref=br_asw_pdt-5?tag=ca-sams-shop",
    )
    # keep node (BrowseNodeSearch) query parameter
    expect(r("https://www.amazon.com/b?ie=UTF8&node=13548845011")).to eq(
      "https://www.amazon.com/b?tag=sams-shop&node=13548845011",
    )

    # Test Indian Amazon domain support
    expect(r("https://www.amazon.in/some_product?xyz=1")).to eq(
      "https://www.amazon.in/some_product?tag=in-sams-shop",
    )
    expect(r("https://amazon.in/some_product")).to eq(
      "https://amazon.in/some_product?tag=in-sams-shop",
    )
  end

  describe "Amazon short links" do
    before do
      SiteSetting.affiliate_amazon_com = "sams-shop"
      SiteSetting.affiliate_amazon_eu = "eu-sams-shop"
      SiteSetting.affiliate_amazon_in = "in-sams-shop"
    end

    it "rewrites a short link to the tagged product page its redirect names" do
      stub_request(:get, "https://amzn.in/d/03WoItOb").to_return(
        status: 301,
        headers: {
          "Location" =>
            "https://www.amazon.in/dp/B0DRYSTF21?ref=cm_sw_r_cso_cp_apan_dp_SNJ9E03JJYYM98KP4Y79&social_share=cm_sw_r_cso_cp_apan_dp_SNJ9E03JJYYM98KP4Y79",
        },
      )
      stub_request(:get, "https://amzn.to/3abcdEF").to_return(
        status: 302,
        headers: {
          "Location" =>
            "https://www.amazon.com/Some-Product/gp/product/B07BP3J6RG/ref=x?tag=bobs-shop",
        },
      )
      stub_request(:get, "https://a.co/d/storefront").to_return(
        status: 301,
        headers: {
          "Location" => "https://www.amazon.com/stores/page/ABC?tag=bobs-shop",
        },
      )

      expect(r("https://amzn.in/d/03WoItOb")).to eq(
        "https://www.amazon.in/dp/B0DRYSTF21?tag=in-sams-shop",
      )
      expect(r("https://amzn.to/3abcdEF")).to eq(
        "https://www.amazon.com/dp/B07BP3J6RG?tag=sams-shop",
      )
      expect(r("https://a.co/d/storefront")).to eq(
        "https://www.amazon.com/stores/page/ABC?tag=sams-shop",
      )
    end

    it "follows a short link that redirects to another short link" do
      stub_request(:get, "https://amzn.eu/d/hop").to_return(
        status: 301,
        headers: {
          "Location" => "https://amzn.in/d/landed",
        },
      )
      stub_request(:get, "https://amzn.in/d/landed").to_return(
        status: 301,
        headers: {
          "Location" => "https://www.amazon.in/dp/B0DRYSTF21",
        },
      )

      expect(r("https://amzn.eu/d/hop")).to eq(
        "https://www.amazon.in/dp/B0DRYSTF21?tag=in-sams-shop",
      )
    end

    it "tags the short link as written when it does not lead to a store page" do
      stub_request(:get, "https://amzn.com/dead?xyz=1").to_return(status: 404)
      stub_request(:get, "https://amzn.eu/d/slow").to_timeout
      stub_request(:get, "https://amzn.to/frontpage").to_return(
        status: 302,
        headers: {
          "Location" => "http://www.amazon.com/",
        },
      )
      stub_request(:get, "https://a.co/d/elsewhere").to_return(
        status: 301,
        headers: {
          "Location" => "https://example.com/dp/B0DRYSTF21",
        },
      )
      stub_request(:get, "https://amzn.in/d/loop").to_return(
        status: 301,
        headers: {
          "Location" => "https://amzn.in/d/loop",
        },
      )

      expect(r("https://amzn.com/dead?xyz=1")).to eq("https://amzn.com/dead?tag=sams-shop")
      expect(r("https://amzn.eu/d/slow")).to eq("https://amzn.eu/d/slow?tag=eu-sams-shop")
      expect(r("https://amzn.to/frontpage")).to eq("https://amzn.to/frontpage?tag=sams-shop")
      expect(r("https://a.co/d/elsewhere")).to eq("https://a.co/d/elsewhere?tag=sams-shop")
      expect(r("https://amzn.in/d/loop")).to eq("https://amzn.in/d/loop?tag=in-sams-shop")
    end

    it "asks Amazon once for a short link it has already expanded" do
      expansion =
        stub_request(:get, "https://amzn.in/d/once").to_return(
          status: 301,
          headers: {
            "Location" => "https://www.amazon.in/dp/B0DRYSTF21",
          },
        )

      2.times { r("https://amzn.in/d/once") }

      expect(expansion).to have_been_requested.once
    end
  end

  it "can apply codes to post in post processor" do
    Jobs.run_immediately!
    SiteSetting.affiliate_amazon_com = "sams-shop"

    stub_request(:get, "http://www.amazon.com/link?testing").to_return(status: 200, body: "")
    post = create_post(raw: "this is an www.amazon.com/link?testing yay")
    post.reload

    expect(post.cooked.scan("sams-shop").length).to eq(1)
  end
end
