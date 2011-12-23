require 'spec/spec_helper'

describe Search do
  fixtures :affiliates, :misspellings, :popular_image_queries

  before do
    @affiliate = affiliates(:basic_affiliate)
    @valid_options = {:query => 'government', :page => 3}
  end

  describe "#run" do
    it "should instrument the call to Bing with the proper action.service namespace and query param hash" do
      ActiveSupport::Notifications.should_receive(:instrument).
        with("bing_search.usasearch", hash_including(:query => hash_including(:term => an_instance_of(String))))
      Search.new(@valid_options).run
    end

    context "when Bing returns zero results" do
      before do
        @search = Search.new(@valid_options.merge(:query => 'abydkldkd'))
      end

      it "should still return true when searching" do
        @search.run.should be_true
      end

      it "should populate additional results" do
        @search.should_receive(:populate_additional_results).and_return true
        @search.run
      end
    end

    context "when response body is nil from Bing" do
      before do
        JSON.should_receive(:parse).once.and_return nil
        @search = Search.new(@valid_options)
      end

      it "should still return true when searching" do
        @search.run.should be_true
      end

      it "should populate additional results" do
        @search.should_receive(:populate_additional_results).and_return true
        @search.run
      end
    end

    context "when JSON cannot be parsed for some reason" do
      before do
        JSON.should_receive(:parse).once.and_raise(JSON::ParserError)
        @search = Search.new(@valid_options)
      end

      it "should return false when searching" do
        @search.run.should be_false
      end

      it "should log a warning" do
        Rails.logger.should_receive(:warn)
        @search.run
      end
    end

    context "when a SocketError occurs" do
      before do
        @search = Search.new(@valid_options)
        Net::HTTP::Get.stub!(:new).and_raise SocketError
      end

      it "should return false when searching" do
        @search.run.should be_false
      end
    end

    context "when Bing gives us the hand" do
      before do
        @search = Search.new(@valid_options)
        Net::HTTP::Get.stub!(:new).and_raise Errno::ECONNREFUSED
      end

      it "should return false when searching" do
        @search.run.should be_false
      end

    end

    context "when Akamai DNS sends us to an unreachable IP address for api.bing.net" do
      before do
        @search = Search.new(@valid_options)
        Net::HTTP::Get.stub!(:new).and_raise Errno::EHOSTUNREACH
      end

      it "should return false when searching" do
        @search.run.should be_false
      end

    end

    context "when Bing kicks us to the curb" do
      before do
        @search = Search.new(@valid_options)
        Net::HTTP::Get.stub!(:new).and_raise Errno::ECONNRESET
      end

      it "should return false when searching" do
        @search.run.should be_false
      end

    end

    context "when Bing takes waaaaaaaaay to long to respond" do
      context "and throws a Timeout::Error" do
        before do
          @search = Search.new(@valid_options)
          Net::HTTP::Get.stub!(:new).and_raise Timeout::Error
        end

        it "should return false when searching" do
          @search.run.should be_false
        end
      end

      context "and throws a Errno::ETIMEDOUT error" do
        before do
          @search = Search.new(@valid_options)
          Net::HTTP::Get.stub!(:new).and_raise Errno::ETIMEDOUT
        end

        it "should return false when searching" do
          @search.run.should be_false
        end
      end

    end

    context "when Bing stops talking in mid-sentence" do
      before do
        @search = Search.new(@valid_options)
        Net::HTTP::Get.stub!(:new).and_raise EOFError
      end

      it "should return false when searching" do
        @search.run.should be_false
      end

    end

    context "when Bing is unreachable" do
      before do
        @search = Search.new(@valid_options)
        Net::HTTP::Get.stub!(:new).and_raise Errno::ENETUNREACH
      end

      it "should return false when searching" do
        @search.run.should be_false
      end
    end

    context "when enable highlighting is set to true" do
      it "should pass the enable highlighting parameter to Bing as an option" do
        uriresult = URI::parse("http://localhost:3000")
        search = Search.new(@valid_options.merge(:enable_highlighting => true))
        URI.should_receive(:parse).with(/EnableHighlighting/).and_return(uriresult)
        search.run
      end
    end

    context "when enable highlighting is set to false" do
      it "should not pass enable highlighting parameter to Bing as an option" do
        uriresult = URI::parse("http://localhost:3000")
        search = Search.new(@valid_options.merge(:enable_highlighting => false))
        URI.should_receive(:parse).with(/Options=&/).and_return(uriresult)
        search.run
      end
    end

    context "when non-English locale is specified" do
      before do
        I18n.locale = :es
      end

      it "should pass a language filter to Bing" do
        uriresult = URI::parse("http://localhost:3000/")
        search = Search.new(@valid_options)
        URI.should_receive(:parse).with(/%20language%3Aes/).and_return(uriresult)
        search.run
      end

      after do
        I18n.locale = I18n.default_locale
      end
    end

    context "when affiliate is not nil" do
      it "should not search for FAQs" do
        search = Search.new(@valid_options.merge(:affiliate => @affiliate))
        Faq.should_not_receive(:search_for)
        search.run
      end

      context "when affiliate has domains specified and user does not specify site: in search" do
        before do
          @affiliate = Affiliate.new(:domains => %w(foo.com bar.com).join("\r\n"))
          @uriresult = URI::parse("http://localhost:3000/")
        end

        it "should use affiliate domains in query to Bing without passing ScopeID" do
          search = Search.new(@valid_options.merge(:affiliate => @affiliate))
          URI.should_receive(:parse).with(/query=\(government\)%20\(site%3Afoo\.com%20OR%20site%3Abar\.com\)$/).and_return(@uriresult)
          search.run
        end

        context "when the domains are separated by only '\\n'" do
          before do
            @affiliate.domains = %w(         foo.com bar.com         ).join("\n")
          end

          it "should split the domains the same way" do
            search = Search.new(@valid_options.merge(:affiliate => @affiliate))
            URI.should_receive(:parse).with(/query=\(government\)%20\(site%3Afoo\.com%20OR%20site%3Abar\.com\)$/).and_return(@uriresult)
            search.run
          end
        end

        context "when there are so many domains that the overall query exceeds Bing's limit, generating an error" do
          before do
            @affiliate.domains = "a10001".upto("a10100").collect { |x| "#{x}.gov" }.join("\n")
          end

          it "should use a subset of the affiliate's domains (order is unimportant) up to the predetermined limit, accounting for URI encoding" do
            search = Search.new(@valid_options.merge(:affiliate => @affiliate))
            URI.should_receive(:parse).with(/a10071.gov\)$/).and_return(@uriresult)
            search.run
          end
        end

        context "when a scope id parameter is passed" do
          it "should use the scope id with the default scope and any domains if the scope id is valid" do
            search = Search.new(@valid_options.merge(:affiliate => @affiliate, :scope_id => 'PatentClass'))
            URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3APatentClass%20OR%20site%3Afoo.com%20OR%20site%3Abar.com\)$/).and_return(@uriresult)
            search.run
          end

          it "should use the affiliate's domains if the scope id is not on the list of valid scopes" do
            search = Search.new(@valid_options.merge(:affiliate => @affiliate, :scope_id => 'InvalidScope'))
            URI.should_receive(:parse).with(/query=\(government\)%20\(site%3Afoo\.com%20OR%20site%3Abar\.com\)$/).and_return(@uriresult)
            search.run
          end

          it "should use the affiliates domains if the scope id is empty" do
            search = Search.new(@valid_options.merge(:affiliate => @affiliate, :scope_id => ''))
            URI.should_receive(:parse).with(/query=\(government\)%20\(site%3Afoo\.com%20OR%20site%3Abar\.com\)$/).and_return(@uriresult)
            search.run
          end
        end
      end

      context "when affiliate has domains specified but user specifies site: in search" do
        before do
          @affiliate = Affiliate.new(:domains => %w(foo.com bar.com).join("\n"))
          @uriresult = URI::parse("http://localhost:3000/")
        end

        it "should override affiliate domains in query to Bing and use ScopeID/gov/mil combo" do
          search = Search.new(@valid_options.merge(:affiliate => @affiliate, :query=>"government site:blat.gov"))
          URI.should_receive(:parse).with(/query=\(government%20site%3Ablat\.gov\)$/).and_return(@uriresult)
          search.run
        end

        context "and the affiliate specifies a scope id" do
          it "should use the scope id with the default scope and domains if the scope is valid" do
            search = Search.new(@valid_options.merge(:affiliate => @affiliate, :query=>"government site:blat.gov", :scope_id => 'PatentClass'))
            URI.should_receive(:parse).with(/query=\(government%20site%3Ablat\.gov\)%20\(scopeid%3APatentClass%20OR%20site%3Afoo.com%20OR%20site%3Abar.com\)$/).and_return @uriresult
            search.run
          end

          it "should use the default scope if the scope is invalid" do
            search = Search.new(@valid_options.merge(:affiliate => @affiliate, :query=>"government site:blat.gov", :scope_id => 'InvalidScope'))
            URI.should_receive(:parse).with(/query=\(government%20site%3Ablat\.gov\)$/).and_return(@uriresult)
            search.run
          end

          it "should use the default scope if the scope is empty" do
            search = Search.new(@valid_options.merge(:affiliate => @affiliate, :query=>"government site:blat.gov", :scope_id => ''))
            URI.should_receive(:parse).with(/query=\(government%20site%3Ablat\.gov\)$/).and_return(@uriresult)
            search.run
          end
        end
      end

      context "when affiliate has more than one domains specified and sitelimit contains one matching domain" do
        let(:affiliate) { mock('affiliate', :domains => %w(foo.com bar.com).join("\r\n")) }
        let(:search) { Search.new(@valid_options.merge(:affiliate => affiliate, :site_limits => 'www.foo.com')) }

        before do
          affiliate.should_receive(:get_matching_domain).with("www.foo.com").and_return("foo.com")
          uri_result = URI::parse("http://localhost:3000/")
          URI.should_receive(:parse).with(/#{Regexp.escape("(government)%20(site%3Awww.foo.com)")}/).and_return(uri_result)
          search.run
        end

        subject { search }
        its(:query) { should == 'government' }
        its(:formatted_query) { should == '(government) (site:www.foo.com)' }
        its(:matching_site_limit) { should == 'www.foo.com' }
      end

      context "when affiliate has more than one domains specified and sitelimit does not contain matching domain" do
        let(:affiliate) { mock('affiliate', :domains => %w(foo.com bar.com).join("\r\n")) }
        let(:search) { Search.new(@valid_options.merge(:affiliate => affiliate, :site_limits => 'doesnotexist.gov')) }

        before do
          affiliate.should_receive(:get_matching_domain).with("doesnotexist.gov").and_return(nil)
          uri_result = URI::parse("http://localhost:3000/")
          URI.should_receive(:parse).with(/#{Regexp.escape("(government)%20(site%3Afoo.com%20OR%20site%3Abar.com)")}/).and_return(uri_result)
          search.run
        end

        subject { search }
        its(:query) { should == 'government' }
        its(:formatted_query) { should == '(government) (site:foo.com OR site:bar.com)' }
        its(:matching_site_limit) { should be_blank }
      end

      context "when affiliate has no domains specified" do
        before do
          @uriresult = URI::parse("http://localhost:3000/")
        end

        it "should use just query string and ScopeID/gov/mil combo" do
          search = Search.new(@valid_options.merge(:affiliate => Affiliate.new))
          URI.should_receive(:parse).with(/query=\(government\)$/).and_return(@uriresult)
          search.run
        end

        context "when a scope id is provided" do
          it "should use the scope id with the default scope if the scope id provided is valid" do
            search = Search.new(@valid_options.merge(:affiliate => Affiliate.new, :scope_id => 'PatentClass'))
            URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3APatentClass\)$/).and_return(@uriresult)
            search.run
          end

          it "should ignore the scope id if it's not on the list of valid scopes" do
            search = Search.new(@valid_options.merge(:affiliate => Affiliate.new, :scope_id => 'InvalidScope'))
            URI.should_receive(:parse).with(/query=\(government\)$/).and_return(@uriresult)
            search.run
          end

          it "should ignore the scope id if it's empty" do
            search = Search.new(@valid_options.merge(:affiliate => Affiliate.new, :scope_id => ''))
            URI.should_receive(:parse).with(/query=\(government\)$/).and_return(@uriresult)
            search.run
          end
        end
      end
    end

    context "when affiliate is nil" do
      before do
        @search = Search.new(@valid_options.merge(:affiliate => nil))
      end

      it "should use just query string and ScopeID/gov/mil combo" do
        uriresult = URI::parse("http://localhost:3000/")
        URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)$/).and_return(uriresult)
        @search.run
      end

      it "should search for FAQs" do
        Faq.should_receive(:search_for).with('government', I18n.default_locale.to_s)
        @search.run
      end

      context "when a scope id is specified" do
        it "should ignore the scope id" do
          uriresult = URI::parse("http://localhost:3000/")
          @search = Search.new(@valid_options.merge(:affiliate => nil, :scope_id => 'PatentClass'))
          URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)$/).and_return(uriresult)
          @search.run
        end
      end
    end

    context "when page offset is specified" do
      it "should specify the offset in the query to Bing" do
        uriresult = URI::parse("http://localhost:3000/")
        search = Search.new(@valid_options.merge(:page => 7))
        URI.should_receive(:parse).with(/web\.offset=70/).and_return(uriresult)
        search.run
      end
    end

    context "when advanced query parameters are passed" do
      before do
        @uriresult = URI::parse('http://localhost:3000')
      end

      context "when query is limited to search only in titles" do
        it "should construct a query string with the intitle: limits on the query parameter" do
          search = Search.new(@valid_options.merge(:query_limit => "intitle:"))
          URI.should_receive(:parse).with(/query=\(intitle%3Agovernment\)/).and_return(@uriresult)
          search.run
        end

        context "when more than one query term is specified" do
          it "should construct a query string with intitle: limits before each query term" do
            search = Search.new(@valid_options.merge(:query => 'barack obama', :query_limit => 'intitle:'))
            URI.should_receive(:parse).with(/query=\(intitle%3Abarack%20intitle%3Aobama\)/).and_return(@uriresult)
            search.run
          end
        end

        context "when query limit is blank" do
          it "should not use the query limit in the query string" do
            search = Search.new(@valid_options.merge(:query_limit => ''))
            URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)/).and_return(@uriresult)
            search.run
          end
        end
      end

      context "when a phrase query is specified" do
        it "should construct a query string that includes the phrase in quotes" do
          search = Search.new(@valid_options.merge(:query_quote => 'barack obama'))
          URI.should_receive(:parse).with(/%22barack%20obama%22/).and_return(@uriresult)
          search.run
        end

        context "when the phrase query limit is set to intitle:" do
          it "should construct a query string with the intitle: limit on the phrase query" do
            search = Search.new(@valid_options.merge(:query_quote => 'barack obama', :query_quote_limit => 'intitle:'))
            URI.should_receive(:parse).with(/%20intitle%3A%22barack%20obama%22/).and_return(@uriresult)
            search.run
          end
        end

        context "and it is blank" do
          it "should not include a phrase query in the url" do
            search = Search.new(@valid_options.merge(:query_quote => ''))
            URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)/).and_return(@uriresult)
            search.run
          end
        end

        context "when the phrase query is blank and the phrase query limit is blank" do
          it "should not include anything relating to phrase query in the query string" do
            search = Search.new(@valid_options.merge(:query_quote => '', :query_quote_limit => ''))
            URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)/).and_return(@uriresult)
            search.run
          end
        end
      end

      context "when OR terms are specified" do
        it "should construct a query string that includes the OR terms OR'ed together" do
          search = Search.new(@valid_options.merge(:query_or => 'barack obama'))
          URI.should_receive(:parse).with(/barack%20OR%20obama/).and_return(@uriresult)
          search.run
        end

        context "when the OR query limit is set to intitle:" do
          it "should construct a query string that includes the OR terms with intitle prefix" do
            search = Search.new(@valid_options.merge(:query_or => 'barack obama', :query_or_limit => 'intitle:'))
            URI.should_receive(:parse).with(/intitle%3Abarack%20OR%20intitle%3Aobama/).and_return(@uriresult)
            search.run
          end
        end

        context "when the OR query is blank" do
          it "should not include an OR query parameter in the query string" do
            search = Search.new(@valid_options.merge(:query_or => ''))
            URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)/).and_return(@uriresult)
            search.run
          end
        end

        context "when the OR query is blank and the OR query limit is blank" do
          it "should not include anything relating to OR query in the query string" do
            search = Search.new(@valid_options.merge(:query_or => '', :query_or_limit => ''))
            URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)/).and_return(@uriresult)
            search.run
          end
        end
      end

      context "when negative query terms are specified" do
        it "should construct a query string that includes the negative query terms prefixed with '-'" do
          search = Search.new(@valid_options.merge(:query_not => 'barack obama'))
          URI.should_receive(:parse).with(/-barack%20-obama/).and_return(@uriresult)
          search.run
        end

        context "when the negative query limit is set to intitle:" do
          it "should construct a query string that includes the negative terms with intitle prefix" do
            search = Search.new(@valid_options.merge(:query_not => 'barack obama', :query_not_limit => 'intitle:'))
            URI.should_receive(:parse).with(/-intitle%3Abarack%20-intitle%3Aobama/).and_return(@uriresult)
            search.run
          end
        end

        context "when the negative query is blank" do
          it "should not include a negative query parameter in the query string" do
            search = Search.new(@valid_options.merge(:query_not => ''))
            URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)/).and_return(@uriresult)
            search.run
          end
        end

        context "when the negative query is blank and the negative query limit are blank" do
          it "should not include anything relating to negative query in the query string" do
            search = Search.new(@valid_options.merge(:query_not => '', :query_not_limit => ''))
            URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)/).and_return(@uriresult)
            search.run
          end
        end
      end

      context "when a filetype is specified" do
        it "should construct a query string that includes a filetype" do
          search = Search.new(@valid_options.merge(:file_type => 'pdf'))
          URI.should_receive(:parse).with(/filetype%3Apdf/).and_return(@uriresult)
          search.run
        end

        context "when the filetype specified is 'All'" do
          it "should construct a query string that does not have a filetype parameter" do
            search = Search.new(@valid_options.merge(:file_type => 'All'))
            URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)/).and_return(@uriresult)
            search.run
          end
        end

        context "when a blank filetype is passed in" do
          it "should not put filetype parameters in the query string" do
            search = Search.new(@valid_options.merge(:file_type => ''))
            URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)/).and_return(@uriresult)
            search.run
          end
        end
      end

      context "when one or more site limits are specified" do
        it "should construct a query string with site limits for each of the sites" do
          search = Search.new(@valid_options.merge(:site_limits => 'whitehouse.gov omb.gov'))
          URI.should_receive(:parse).with(/site%3Awhitehouse.gov%20OR%20site%3Aomb.gov/).and_return(@uriresult)
          search.run
        end

        context "when a blank site limit is passed" do
          it "should not include site limit in the query string" do
            search = Search.new(@valid_options.merge(:site_limits => ''))
            URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)/).and_return(@uriresult)
            search.run
          end
        end
      end

      context "when one or more site exclusions is specified" do
        it "should construct a query string with site exlcusions for each of the sites" do
          search = Search.new(@valid_options.merge(:site_excludes => "whitehouse.gov omb.gov"))
          URI.should_receive(:parse).with(/-site%3Awhitehouse.gov%20-site%3Aomb.gov/).and_return(@uriresult)
          search.run
        end

        context "when a blank site exclude is passed" do
          it "should not include site exclude in the query string" do
            search = Search.new(@valid_options.merge(:site_excludes => ''))
            URI.should_receive(:parse).with(/query=\(government\)%20\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)/).and_return(@uriresult)
            search.run
          end
        end
      end

      context "when a fedstates parameter is specified" do
        it "should set the scope if with the fedstates parameter" do
          search = Search.new(@valid_options.merge(:fedstates => 'MD'))
          URI.should_receive(:parse).with(/\(scopeid%3AusagovMD\)/).and_return(@uriresult)
          search.run
        end

        context "when the fedstates parameter specified is 'all'" do
          it "should use the 'usagovall' scopeid with .gov and .mil sites included" do
            search = Search.new(@valid_options.merge(:fedstates => 'all'))
            URI.should_receive(:parse).with(/\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)/).and_return(@uriresult)
            search.run
          end
        end

        context "when fedstates parameter is blank" do
          it "should use the 'usagovall' scope id with .gov and .mil sites included" do
            search = Search.new(@valid_options.merge(:fedstates => ''))
            URI.should_receive(:parse).with(/\(scopeid%3Ausagovall%20OR%20site%3Agov%20OR%20site%3Amil\)/).and_return(@uriresult)
            search.run
          end
        end
      end

      context "when a results per page number is specified" do
        it "should construct a query string with the appropriate per page variable set" do
          search = Search.new(@valid_options.merge(:results_per_page => 20))
          URI.should_receive(:parse).with(/web\.count=20/).and_return(@uriresult)
          search.run
        end

        it "should not set a per page value above 50" do
          search = Search.new(@valid_options.merge(:results_per_page => 100))
          URI.should_receive(:parse).with(/web\.count=50/).and_return(@uriresult)
          search.run
        end

        context "when the results_per_page variable passed is blank" do
          it "should set the per-page parameter to the default value, defined by the DEFAULT_PER_PAGE variable" do
            search = Search.new(@valid_options)
            URI.should_receive(:parse).with(/web\.count=10/).and_return(@uriresult)
            search.run
          end
        end

        context "when the results_per_page variable that is passed is a string" do
          it "should convert the string to an integer and not fail" do
            search = Search.new(@valid_options.merge(:results_per_page => "30"))
            URI.should_receive(:parse).with(/web\.count=30/).and_return(@uriresult)
            search.run
          end
        end
      end

      context "when multiple or all of the advanced query parameters are specified" do
        it "should construct a query string that incorporates all of them with the proper spacing" do
          search = Search.new(@valid_options.merge(:query_limit => 'intitle:',
                                                   :query_quote => 'barack obama',
                                                   :query_quote_limit => '',
                                                   :query_or => 'cars stimulus',
                                                   :query_or_limit => '',
                                                   :query_not => 'clunkers',
                                                   :query_not_limit => 'intitle:',
                                                   :file_type => 'pdf',
                                                   :site_limits => 'whitehouse.gov omb.gov',
                                                   :site_excludes => 'nasa.gov noaa.gov'))
          URI.should_receive(:parse).with(/query=\(intitle%3Agovernment%20%22barack%20obama%22%20cars%20OR%20stimulus%20-intitle%3Aclunkers%20filetype%3Apdf%20site%3Awhitehouse.gov%20OR%20site%3Aomb.gov%20-site%3Anasa.gov%20-site%3Anoaa.gov\)/).and_return(@uriresult)
          search.run
        end
      end

      describe "adult content filters" do
        context "when a valid filter parameter is present" do
          it "should set the Adult parameter in the query sent to Bing" do
            search = Search.new(@valid_options.merge(:filter => 'off'))
            URI.should_receive(:parse).with(/Adult=off/).and_return(@uriresult)
            search.run
          end
        end

        context "when the filter parameter is blank" do
          it "should set the Adult parameter to the default value" do
            search = Search.new(@valid_options.merge(:filter => ''))
            URI.should_receive(:parse).with(/Adult=#{Search::DEFAULT_FILTER_SETTING}/).and_return(@uriresult)
            search.run
          end
        end

        context "when the filter parameter is not in the list of valid filter values" do
          it "should set the Adult parameter to the default value" do
            search = Search.new(@valid_options.merge(:filter => 'invalid'))
            URI.should_receive(:parse).with(/Adult=#{Search::DEFAULT_FILTER_SETTING}/).and_return(@uriresult)
            search.run
          end
        end

        context "when a filter parameter is not set" do
          it "should set the Adult parameter to the default value ('moderate')" do
            search = Search.new(@valid_options)
            URI.should_receive(:parse).with(/Adult=moderate/i).and_return(@uriresult)
            search.run
          end
        end

      end
    end

    describe "Calais Related Searches" do
      context "when performing an uppercase search that has a downcased related topic" do
        before do
          CalaisRelatedSearch.create!(:term=> "whatever", :related_terms => "ridiculous government grants | big government | democracy")
          CalaisRelatedSearch.reindex
          Sunspot.commit
          @search = Search.new(:query=>"Democracy")
          @search.stub!(:coin_toss_heads?).and_return true
          @search.run
        end

        it "should not have the matching related topic in the array of strings" do
          @search.related_search.should == ["big government", "ridiculous government grants"]
        end
      end

      context "when performing a search that has a uppercased related topic" do
        before do
          CalaisRelatedSearch.create!(:term=> "whatever", :related_terms => "Fred Espenak | big government | democracy")
          CalaisRelatedSearch.reindex
          Sunspot.commit
          @search = Search.new(:query=>"Fred Espenak")
          @search.stub!(:coin_toss_heads?).and_return true
          @search.run
        end

        it "should not have the matching related topic in the array of strings" do
          @search.related_search.should == ["big government", "democracy"]
        end
      end

      context "when performing an affiliate search that has related topics" do
        before do
          CalaisRelatedSearch.create!(:term => "pivot term", :related_terms => "government grants | big government | democracy", :affiliate => @affiliate)
          CalaisRelatedSearch.reindex
          Sunspot.commit
        end

        it "should have a related searches array of strings not including the pivot term" do
          search = Search.new(@valid_options.merge(:affiliate => @affiliate))
          search.stub!(:coin_toss_heads?).and_return true
          search.run
          search.related_search.should == ["big government", "democracy", "government grants"]
        end

        context "when there are also related topics for the default affiliate" do
          before do
            CalaisRelatedSearch.create!(:term => "pivot term", :related_terms => "government health care | small government | fascism")
            CalaisRelatedSearch.reindex
            Sunspot.commit
          end

          context "when the affiliate has affiliate related topics enabled" do
            before do
              @affiliate.related_topics_setting = 'affiliate_enabled'
              @affiliate.save
            end

            it "should return the affiliate related topics" do
              search = Search.new(@valid_options.merge(:affiliate => @affiliate))
              search.stub!(:coin_toss_heads?).and_return true
              search.run
              search.related_search.should == ["big government", "democracy", "government grants"]
            end
          end

          context "when the affiliate has global related topics enabled" do
            before do
              @affiliate.related_topics_setting = 'global_enabled'
              @affiliate.save
            end

            it "should return the global related topics" do
              search = Search.new(@valid_options.merge(:affiliate => @affiliate))
              search.stub!(:coin_toss_heads?).and_return true
              search.run
              search.related_search.should == ["fascism", "government health care", "small government"]
            end
          end

          context "when the affiliate has related topics disabled" do
            before do
              @affiliate.related_topics_setting = 'disabled'
              @affiliate.save
            end

            it "should return the affiliate related topics" do
              search = Search.new(@valid_options.merge(:affiliate => @affiliate))
              search.stub!(:coin_toss_heads?).and_return true
              search.run
              search.related_search.should == []
            end
          end
        end
      end

      context "when performing an affiliate search that does not have related topics while the default affiliate does" do
        before do
          CalaisRelatedSearch.create!(:term=> @valid_options[:query], :related_terms => "government grants | big government | democracy")
          CalaisRelatedSearch.reindex
          Sunspot.commit
          @search = Search.new(@valid_options.merge(:affiliate => @affiliate))
          @search.stub!(:coin_toss_heads?).and_return true
          @search.run
        end

        it "should not fall back to the result for the default affiliate" do
          @search.related_search.size.should == 0
        end
      end
    end

    context "when the query contains an '&' character" do
      it "should pass a url-escaped query string to Bing" do
        @uriresult = URI::parse('http://localhost:3000')
        query = "Pros & Cons Physician Assisted Suicide"
        search = Search.new(@valid_options.merge(:query => query))
        URI.should_receive(:parse).with(/Pros%20%26%20Cons%20Physician%20Assisted%20Suicide/).and_return(@uriresult)
        search.run
      end
    end

    context "when the query ends in OR" do
      before do
        CalaisRelatedSearch.create!(:term=> "portland or", :related_terms => %w{ portland or | oregon | rain })
        CalaisRelatedSearch.reindex
        Sunspot.commit
        @search = Search.new(:query => "Portland OR")
        @search.stub!(:coin_toss_heads?).and_return true
        @search.run
      end

      it "should still work (i.e., downcase the query so Solr does not treat it as a Boolean OR)" do
        @search.related_search.size.should == 3
      end
    end

    context "when searching with really long queries" do
      before do
        @search = Search.new(@valid_options.merge(:query => "X" * (Search::MAX_QUERYTERM_LENGTH + 1)))
      end

      it "should return false when searching" do
        @search.run.should be_false
      end

      it "should have 0 results" do
        @search.run
        @search.results.size.should == 0
      end

      it "should set error message" do
        @search.run
        @search.error_message.should_not be_nil
      end
    end

    context "when searching with nonsense queries" do
      before do
        @search = Search.new(@valid_options.merge(:query => 'kjdfgkljdhfgkldjshfglkjdsfhg'))
      end

      it "should return true when searching" do
        @search.run.should be_true
      end

      it "should have 0 results" do
        @search.run
        @search.results.size.should == 0
      end
    end

    context "when results contain listing missing a title" do
      before do
        @search = Search.new(@valid_options.merge(:query => 'Nas & Kelis'))
        json = File.read(Rails.root.to_s + "/spec/fixtures/json/bing_two_search_results_one_missing_title.json")
        parsed = JSON.parse(json)
        JSON.stub!(:parse).and_return parsed
      end

      it "should ignore that result" do
        @search.run
        @search.results.size.should == 1
      end
    end

    context "when results contain listing missing a description" do
      before do
        @search = Search.new(@valid_options.merge(:query => 'data'))
        json = File.read(Rails.root.to_s + "/spec/fixtures/json/bing_search_results_with_some_missing_descriptions.json")
        parsed = JSON.parse(json)
        JSON.stub!(:parse).and_return parsed
      end

      it "should use a blank description" do
        @search.run
        @search.results.size.should == 10
        @search.results.each do |result|
          result['content'].should == ""
        end
      end
    end

    context "when Bing results contain excluded URLs" do
      before do
        @url1 = "http://www.uspto.gov/web.html"
        @url2 = "http://www.windstream.net/web.html"
        affiliate = affiliates(:power_affiliate)
        ExcludedDomain.create!(:domain => "windstream.net")
        ExcludedUrl.create!(:url => @url1, :affiliate => affiliate)
        @search = Search.new(@valid_options.merge(:query => '(electro coagulation) site:uspto.gov', :affiliate => affiliate))
        json = File.read(Rails.root.to_s + "/spec/fixtures/json/bing_search_results_with_spelling_suggestions.json")
        parsed = JSON.parse(json)
        JSON.stub!(:parse).and_return parsed
        @search.run
      end

      it "should filter out the excluded URLs" do
        @search.results.any? {|result| result['unescapedUrl'] == @url1 or result['unescapedUrl'] == @url2 }.should be_false
        @search.results.size.should == 4
      end

    end

    context "when searching for misspelled terms" do
      before do
        @search = Search.new(@valid_options.merge(:query => "p'resident"))
        json = File.read(Rails.root.to_s + "/spec/fixtures/json/bing_search_results_with_spelling_suggestions_pres.json")
        parsed = JSON.parse(json)
        JSON.stub!(:parse).and_return parsed
        @search.run
      end

      it "should have spelling suggestions" do
        @search.spelling_suggestion.should == "president"
      end
    end

    context "when suggestions for misspelled terms contain scopeid or parenthesis" do
      before do
        @search = Search.new(@valid_options.merge(:query => '(electro coagulation) site:uspto.gov'))
        json = File.read(Rails.root.to_s + "/spec/fixtures/json/bing_search_results_with_spelling_suggestions.json")
        parsed = JSON.parse(json)
        JSON.stub!(:parse).and_return parsed
        @search.run
      end

      it "should strip them all out, leaving site: terms in the suggestion" do
        @search.spelling_suggestion.should == "electrocoagulation site:uspto.gov"
      end
    end

    context "when the Bing spelling suggestion is identical to the original query except for Bing highight characters" do
      before do
        @search = Search.new(:query => 'ct-w4')
        json = File.read(Rails.root.to_s + "/spec/fixtures/json/bing_search_results_with_spelling_suggestion_containing_highlight_characters.json")
        parsed = JSON.parse(json)
        JSON.stub!(:parse).and_return parsed
        @search.run
      end

      it "should not have a spelling suggestion" do
        @search.spelling_suggestion.should be_nil
      end
    end

    context "when the Bing spelling suggestion is identical to the original query except for a hyphen" do
      before do
        @search = Search.new(:query => 'bio-tech')
        json = File.read(Rails.root.to_s + "/spec/fixtures/json/bing_search_results_with_spelling_suggestion_containing_a_hyphen.json")
        parsed = JSON.parse(json)
        JSON.stub!(:parse).and_return parsed
        @search.run
      end

      it "should not have a spelling suggestion" do
        @search.spelling_suggestion.should be_nil
      end
    end

    context "recent recalls" do
      before :each do
        @options_with_recall = {:query => "foo bar recall"}
      end

      it "should send the query to recall" do
        search = Search.new(@options_with_recall)
        results = [1, 2, 3]
        Recall.should_receive(:recent).with('foo bar recall').and_return(results)
        search.run
        search.recalls.should == results
      end

      it "should not run on pages other than the first page" do
        search = Search.new(@options_with_recall.merge(:page => 2))
        Recall.should_not_receive(:recent)
        search.run
      end

      it "should not run on affiliate pages" do
        search = Search.new(@options_with_recall.merge(:affiliate => @affiliate))
        Recall.should_not_receive(:recent)
        search.run
      end
    end

    context "popular image searches" do
      it "should try to find images when searching for a popular image" do
        search = Search.new(:query => popular_image_queries(:snowflake).query)
        search.run
        search.extra_image_results.should_not be_nil
      end

      it "should try to find images when searching for a popular image when no page param is passed in as an HTTP param" do
        search = Search.new(:query => popular_image_queries(:snowflake).query, :page => -1)
        search.run
        search.extra_image_results.should_not be_nil
      end

      it "should never show extra image results on any page but the first" do
        search = Search.new(:query => popular_image_queries(:snowflake).query, :page => 2)
        search.run
        search.extra_image_results.should be_nil
      end

      it "should never show extra image results if it is not a popular image query" do
        search = Search.new(:query => "non popular image query", :page => 0)
        search.run
        search.extra_image_results.should be_nil
      end

      context "when non-English locale is specified" do
        before do
          I18n.locale = :es
        end

        it "should not show image results if none are returned" do
          popular_query_with_no_results = PopularImageQuery.create(:query => ".416 barret round")
          search = Search.new(@valid_options.merge(:query => popular_query_with_no_results.query, :page => 0))
          search.run
          search.extra_image_results.should be_nil
        end

        after do
          I18n.locale = I18n.default_locale
        end
      end
    end

    context "when paginating" do
      default_page = 0

      it "should default to page 0 if no valid page number was specified" do
        options_without_page = @valid_options.reject { |k, v| k == :page }
        Search.new(options_without_page).page.should == default_page
        Search.new(@valid_options.merge(:page => '')).page.should == default_page
        Search.new(@valid_options.merge(:page => 'string')).page.should == default_page
      end

      it "should set the page number" do
        search = Search.new(@valid_options.merge(:page => 2))
        search.page.should == 2
      end

      it "should use the underlying engine's results per page" do
        search = Search.new(@valid_options)
        search.run
        search.results.size.should == Search::DEFAULT_PER_PAGE
      end

      it "should set startrecord/endrecord" do
        page = 7
        search = Search.new(@valid_options.merge(:page => page))
        search.run
        search.startrecord.should == Search::DEFAULT_PER_PAGE * page + 1
        search.endrecord.should == search.startrecord + search.results.size - 1
      end

      context "when the page is greater than the number of results" do
        before do
          @search = Search.new(@valid_options.merge(:query => 'data'))
          json = File.read(Rails.root.to_s + "/spec/fixtures/json/bing_results_for_a_large_result_set.json")
          parsed = JSON.parse(json)
          JSON.stub!(:parse).and_return parsed
        end

        it "should use Bing's info to set the pagination" do
          search = Search.new(:query => 'government', :page => 97)
          search.run.should be_true
          search.startrecord.should == 621
          search.endrecord.should == 622
        end
      end
    end

    context "when the query matches an agency name or abbreviation" do
      before do
        Agency.destroy_all
        AgencyQuery.destroy_all
        @agency = Agency.create!(:name => 'Internal Revenue Service', :domain => 'irs.gov', :phone => '888-555-1040')
        @agency.agency_urls << AgencyUrl.new(:url => 'http://www.myagency.gov/', :locale => 'en')
        AgencyQuery.create!(:phrase => 'irs', :agency => @agency)
      end

      it "should retrieve the associated agency record" do
        search = Search.new(:query => 'irs')
        search.run
        search.agency.should == @agency
      end

      context "when the query matches but the case is different" do
        it "should match the agency anyway" do
          search = Search.new(:query => 'IRS')
          search.run
          search.agency.should == @agency
        end
      end

      context "when there are leading or trailing spaces, but the query basically matches" do
        it "should match the proper agency anyway" do
          search = Search.new(:query => '     irs   ')
          search.run
          search.agency.should == @agency
        end
      end
    end

    context "med topics" do
      fixtures :med_topics
      before do
        @ulcerative_colitis_med_topic = med_topics(:ulcerative_colitis)
        @ulcerative_colitis_es_med_topic = med_topics(:ulcerative_colitis_es)
      end

      context "when the search matches a MedTopic record" do
        before do
          @search = Search.new(:query => 'ulcerative colitis')
          @search.run
        end

        it "should retrieve the associated Med Topic record" do
          @search.med_topic.should == @ulcerative_colitis_med_topic
        end
      end

      context "when the locale is not the default" do
        before do
          I18n.locale = :es
          @search = Search.new(:query => 'Colitis ulcerativa')
          @search.run
        end

        it "should retrieve the spanish version of the med topic" do
          @search.med_topic.should == @ulcerative_colitis_es_med_topic
        end

        after do
          I18n.locale = I18n.default_locale
        end
      end

      context "when the page is not the first page" do
        before do
          @search = Search.new(:query => 'ulcerative colitis', :page => 3)
          @search.run
        end

        it "should not set the med topic" do
          @search.med_topic.should be_nil
        end
      end

      context "when the query does not match a med topic" do
        before do
          @search = Search.new(:query => 'government')
          @search.run
        end

        it "should not set the med topic" do
          @search.med_topic.should be_nil
        end
      end

      context "when the search matches a med topic, but includes an affiliate" do
        before do
          @search = Search.new(:query => 'ulcerative colitis', :affiliate => affiliates(:basic_affiliate))
          @search.run
        end

        it "should not set a med topic" do
          @search.med_topic.should be_nil
        end
      end
    end

    context "featured collection" do
      context "searching for non affiliate results" do
        let(:search) { Search.new(:query => 'cyclone') }
        let(:featured_collections) { mock('featured collections') }

        before do
          FeaturedCollection.should_receive(:search_for).and_return(featured_collections)
        end

        it "should assign featured collection" do
          search.run
          search.featured_collections.should_not be_nil
        end
      end

      context "searching for affiliate results" do
        context "on the first page" do
          let(:affiliate) { affiliates(:basic_affiliate) }
          let(:search) { Search.new(:affiliate => affiliate, :query => 'cyclone') }
          let(:featured_collections) { mock('featured collections') }

          before do
            FeaturedCollection.should_receive(:search_for).and_return(featured_collections)
          end

          it "should assign featured collection on first page" do
            search.run
            search.featured_collections.should == featured_collections
          end
        end

        context "not on the first page" do
          let(:affiliate) { affiliates(:basic_affiliate) }
          let(:search) { Search.new(:affiliate => affiliate, :query => 'cyclone', :page => 2) }

          before do
            FeaturedCollection.should_not_receive(:search_for)
            search.run
          end

          specify { search.featured_collections.should be_blank }
        end
      end
    end

    context "on normal search runs" do
      before do
        @search = Search.new(@valid_options.merge(:query => 'logme', :affiliate => @affiliate))
        parsed = JSON.parse(File.read(::Rails.root.to_s + "/spec/fixtures/json/bing_search_results_with_spelling_suggestions.json"))
        JSON.stub!(:parse).and_return parsed
      end

      it "should log info about the query" do
        QueryImpression.should_receive(:log).with(:web, @affiliate.name, 'logme', %w{BWEB OVER BSPEL})
        @search.run
      end
    end

    context "when an affiliate has PDF documents" do
      before do
        @affiliate.indexed_documents.destroy_all
        @affiliate.indexed_documents.create(:title => "PDF Title", :description => "PDF Description", :url => 'http://something.gov/pdf1.pdf', :doctype => 'pdf', :last_crawl_status => IndexedDocument::OK_STATUS)
        @affiliate.indexed_documents.create(:title => "PDF Title", :description => "PDF Description", :url => 'http://something.gov/pdf2.pdf', :doctype => 'pdf', :last_crawl_status => IndexedDocument::OK_STATUS)
        IndexedDocument.reindex
        Sunspot.commit
      end

      it "should find PDF documents that match the query if this is the first page" do
        search = Search.new(@valid_options.merge(:query => 'pdf', :affiliate => @affiliate, :page => 0))
        search.run
        search.indexed_documents.should_not be_nil
        search.indexed_documents.count.should == 2
      end

      it "should not find any PDF documents if it's not the first page" do
        search = Search.new(@valid_options.merge(:query => 'pdf', :affiliate => @affiliate, :page => 2))
        search.run
        search.indexed_documents.should be_nil
      end
    end

    context "when an affiliate has Bing results that are duplicated in indexed documents" do
      before do
        @affiliate.indexed_documents.destroy_all
        @affiliate.indexed_documents.create!(:title => "Hack Day - USA.gov Blog", :description => "Hack Day description, sometimes with a trailing slash",
                                             :url => 'http://blog.usa.gov/post/7054661537/1-usa-gov-open-data-and-hack-day', :last_crawl_status => IndexedDocument::OK_STATUS)
        @affiliate.indexed_documents.create!(:title => "Projects created - USA.gov Blog", :description => "Sometimes served up via SSL!",
                                             :url => 'http://blog.usa.gov/post/8522383948/projects-created-at-the-1-usa-gov-hack-day/', :last_crawl_status => IndexedDocument::OK_STATUS)
        @affiliate.indexed_documents.create!(:title => "another one", :description => "Projects created description",
                                             :url => 'http://same-title-and-uri-but-different-host.gov/more?x=4', :last_crawl_status => IndexedDocument::OK_STATUS)
        @affiliate.indexed_documents.create!(:title => "exact url match except for trailing slash", :description => "Projects created description",
                                             :url => 'http://www.gov.gov', :last_crawl_status => IndexedDocument::OK_STATUS)
        IndexedDocument.reindex
        Sunspot.commit
      end

      it "should remove the matching indexed documents" do
        search = Search.new(@valid_options.merge(:query => 'USA.gov blog', :affiliate => @affiliate, :page => 0))
        search.should_receive(:process_results).and_return([{'title' => 'another one', 'unescapedUrl' => 'http://blog.usa.gov/more?x=4#anchor'},
                                                            {'title' => 'Hack Day - USA.gov Blog', 'unescapedUrl' => 'http://usa.gov/post/7054661537/1-usa-gov-open-data-and-hack-day/subdir'},
                                                            {'title' => 'exact url match', 'unescapedUrl' => 'http://www.gov.gov/'},
                                                            {'title' => 'Projects created - USA.gov Blog', 'unescapedUrl' => 'https://blog.usa.gov/post/8522383948/projects-created-at-the-1-usa-gov-hack-day'}])
        search.run
        search.results.count.should == 4
        search.indexed_documents.count.should == 1
        search.indexed_documents.first.instance.url.should == 'http://blog.usa.gov/post/7054661537/1-usa-gov-open-data-and-hack-day'
      end
    end

    context "when the affiliate has no Bing results, and has boosted contents" do
      before do
        IndexedDocument.delete_all
        @non_affiliate = affiliates(:non_existant_affiliate)
        @non_affiliate.indexed_documents.destroy_all
        1.upto(15) do |index|
          @non_affiliate.indexed_documents << IndexedDocument.new(:title => "Indexed Result #{index}", :url => "http://nonsense.com/#{index}.html", :description => 'This is an indexed result.', :last_crawl_status => IndexedDocument::OK_STATUS)
        end
        IndexedDocument.reindex
        Sunspot.commit
        @non_affiliate.indexed_documents.size.should == 15
        IndexedDocument.search_for('indexed', @non_affiliate).total.should == 15
      end

      it "should fill the results with paged boosted results" do
        search = Search.new(:query => 'indexed', :affiliate => @non_affiliate)
        search.run
        search.results.should_not be_nil
        search.results.should_not be_empty
        search.total.should == 15
        search.startrecord.should == 1
        search.endrecord.should == 10
        search.results.first['unescapedUrl'].should == "http://nonsense.com/1.html"
        search.results.last['unescapedUrl'].should == "http://nonsense.com/10.html"
        search.indexed_documents.should be_nil
        search.are_results_by_bing?.should be_false
      end
    end

    context "when affiliate has no Bing results and IndexedDocuments search returns nil" do
      before do
        @non_affiliate = affiliates(:non_existant_affiliate)
        @non_affiliate.boosted_contents.destroy_all
        IndexedDocument.reindex
        Sunspot.commit
        IndexedDocument.stub!(:search_for).and_return nil
      end

      it "should return a search with a zero total" do
        search = Search.new(:query => 'some bogus + + query', :affiliate => @non_affiliate)
        search.run
        search.total.should == 0
        search.results.should_not be_nil
        search.results.should be_empty
        search.startrecord.should be_nil
        search.endrecord.should be_nil
      end
    end
  end

  describe "when new" do
    it "should have a settable query" do
      search = Search.new(@valid_options)
      search.query.should == 'government'
    end

    it "should have a settable affiliate" do
      search = Search.new(@valid_options.merge(:affiliate => @affiliate))
      search.affiliate.should == @affiliate
    end

    it "should not require a query or affiliate" do
      lambda { Search.new }.should_not raise_error(ArgumentError)
    end
  end

  describe "#suggestions(affiliate_id, sanitized_query, num_suggestions)" do
    before do
      phrase = "aaaazy"
      popularity = 10
      16.times { SaytSuggestion.create!(:phrase => phrase.succ!, :popularity => (popularity = popularity.succ)) }
    end

    it "should default to returning 15 suggestions" do
      Search.suggestions(nil, "aaa").size.should == 15
    end

    it "should accept an override for number of suggestions to return" do
      Search.suggestions(nil, "aaa", 6).size.should == 6
    end

    it "should run the words in the query phrase against the misspellings list" do
      SaytSuggestion.create!(:phrase => "obama president")
      Search.suggestions(nil, "ubama pres").first.phrase.should == "obama president"
    end

    context "when no suggestions exist for the query" do
      it "should return an empty array" do
        Search.suggestions(nil, "nothing to see here").should == []
      end
    end

    it "should use affiliate_id to find suggestions" do
      SaytSuggestion.should_receive(:like).with(370, "xyz", 5)
      Search.suggestions(370, "xyz", 5)
    end
  end

  describe "#sources" do
    it "should default to 'Spell+Web'" do
      search = Search.new(:query => 'non-popular image')
      search.sources.should == "Spell+Web"
    end

    it "should be 'Spell+Web+Image' when query is a PopularImageQuery and first page of results and not affiliate scoped" do
      search = Search.new(:query => 'snowflake')
      search.sources.should == "Spell+Web+Image"
    end

    it "should be 'Spell+Web' for affilitate searches, even when the query is a PopularImageQuery and on first page of results" do
      search = Search.new(:query => 'snowflake', :affiliate => @affiliate)
      search.sources.should == "Spell+Web"
    end
  end

  describe "#hits(response)" do
    context "when Bing reports a total > 0 but gives no results whatsoever" do
      before do
        @search = Search.new
        @response = mock("response")
        web = mock("web")
        @response.stub!(:web).and_return(web)
        web.stub!(:results).and_return(nil)
        web.stub!(:total).and_return(4000)
      end

      it "should return zero for the number of hits" do
        @search.send(:hits, @response).should == 0
      end
    end
  end

  describe "#as_json" do
    before do
      affiliate = affiliates(:basic_affiliate)
      affiliate.boosted_contents.create!(:title => "title", :url => "http://example.com", :description => "description", :locale => 'en',
                                         :locale => 'en', :status => 'active', :publish_start_on => Date.current)
      BoostedContent.reindex
      Sunspot.commit
      @search = Search.new(:query => 'obama')
      @search.run
      allow_message_expectations_on_nil
    end

    it "should generate a JSON representation of total, start and end records, spelling suggestions, related searches and search results" do
      json = @search.to_json
      json.should =~ /total/
      json.should =~ /startrecord/
      json.should =~ /endrecord/
    end

    context "when an error occurs" do
      before do
        @search.instance_variable_set(:@error_message, "Some error")
      end

      it "should output an error if an error is detected" do
        json = @search.to_json
        json.should =~ /"error":"Some error"/
      end
    end

    context "when boosted content is present" do
      before do
        @search.instance_variable_set(:@boosted_contents, Struct.new(:results).new([1, 2, 3]))
      end

      it "should output as boosted results" do
        @search.as_json[:boosted_results].should == [1, 2, 3]
      end
    end

    context "when related searches are present" do
      before do
        @search.instance_variable_set(:@related_search, ["<strong>foo</strong>", "<strong>foo</strong> is here <strong>again</strong>"])
      end

      it "should remove <strong> HTML formatting" do
        @search.as_json[:related].should == ["foo", "foo is here again"]
      end
    end
  end

  describe "caching in #perform(query_string, offset, enable_highlighting)" do
    before do
      @redis = Search.send(:class_variable_get, :@@redis)
      @search = Search.new(:query => "foo", :results_per_page => 40, :filter => "strict")
      @cache_key = "(foo) (scopeid:usagovall OR site:gov OR site:mil):Spell+Web:0:40:true:strict"
    end

    it "should have a cache_key containing bing query, sources, offset, count, highlighting, adult filter" do
      @search.cache_key.should == @cache_key
    end

    it "should attempt to get the results from the Redis cache" do
      @redis.should_receive(:get).with(@cache_key)
      @search.send(:perform)
    end

    it "should use the Spell+Image source for image searches" do
      @redis.should_receive(:get).with("(foo) (scopeid:usagovall OR site:gov OR site:mil):Spell+Image:75:25:true:moderate")
      image_search = ImageSearch.new(:query => "foo", :results_per_page => 25, :page => 3)
      image_search.send(:perform)
    end

    context "when no results in cache" do
      it "should store newly fetched results in cache with appropriate expiry" do
        @redis.should_receive(:setex).with(@cache_key, Search::BING_CACHE_DURATION_IN_SECONDS, an_instance_of(String))
        @search.send(:perform)
      end
    end
  end

  describe "#self.results_present_for?(query, affiliate, is_misspelling_allowed)" do
    before do
      @search = Search.new(:affiliate => @affiliate, :query => "some term")
      Search.stub!(:new).and_return(@search)
      @search.stub!(:run).and_return(nil)
    end

    context "when search results exist for a term/affiliate pair" do
      before do
        @search.stub!(:results).and_return([{'title'=>'First title', 'content' => 'First content'},
                                            {'title'=>'Second title', 'content' => 'Second content'}])
      end

      it "should return true" do
        Search.results_present_for?("some term", @affiliate).should be_true
      end

      context "when misspellings aren't allowed" do
        context "when Bing suggests a different spelling" do
          context "when it's a fuzzy match with the query term (ie., identical except for highlights and some punctuation)" do
            before do
              @search.stub!(:spelling_suggestion).and_return "some-term"
            end

            it "should return true" do
              Search.results_present_for?("some term", @affiliate, false).should be_true
            end
          end

          context "when it's not a fuzzy match with the query term" do
            before do
              @search.stub!(:spelling_suggestion).and_return "sum term"
            end

            it "should return false" do
              Search.results_present_for?("some term", @affiliate, false).should be_false
            end
          end
        end

        context "when Bing has no spelling suggestion" do
          before do
            @search.stub!(:spelling_suggestion).and_return nil
          end

          it "should return true" do
            Search.results_present_for?("some term", @affiliate, false).should be_true
          end
        end
      end
    end

    context "when search results do not exist for a term/affiliate pair" do
      before do
        @search.stub!(:results).and_return([])
      end

      it "should return false" do
        Search.results_present_for?("some term", @affiliate).should be_false
      end
    end
  end

  describe "#to_xml" do
    let(:search) { Search.new(:query => 'solar') }
    let(:error_in_xml) { "<search><error>error_message</error></search>" }

    context "when error message exists" do
      before do
        search.run
        search.stub!(:error_message).and_return('error_message')
      end

      specify { search.to_xml.should =~ /#{error_in_xml}/ }
    end

    context "when error message does not exist" do
      let(:keys) { %w(total startrecord endrecord spelling_suggestions related_searches results boosted_results).sort }
      before do
        search.stub!(:total).and_return(100)
        search.stub!(:startrecord).and_return(1)
        search.stub!(:endrecord).and_return(10)
        search.stub!(:results).and_return('results_in_xml')
      end

      specify { Hash.from_xml(search.to_xml)['search'].keys.sort.should == keys }
    end
  end

  describe "#are_results_by_bing?" do
    context "when doing a normal search with normal results" do
      it "should return true" do
        search = Search.new(:query => 'white house')
        search.run
        search.are_results_by_bing?.should be_true
      end
    end

    context "when the Bing results are empty and there are instead locally indexed results" do
      before do
        affiliate = affiliates(:non_existant_affiliate)
        affiliate.indexed_documents << IndexedDocument.new(:url => 'http://some.url.gov/', :title => 'White House Indexed Doc', :description => 'This is an indexed document for the White House.')
        IndexedDocument.reindex
        Sunspot.commit
        @search = Search.new(:query => 'white house', :affiliate => affiliate)
        @search.run
      end

      it "should return false" do
        @search.are_results_by_bing?.should be_false
      end
    end
  end

  describe "#highlight_solr_hit_like_bing" do
    before do
      IndexedDocument.delete_all
      @affiliate = affiliates(:non_existant_affiliate)
      @affiliate.indexed_documents << IndexedDocument.new(:url => 'http://some.url.gov/', :title => 'Highlight me!', :description => 'This doc has highlights.', :body => 'This will match other keywords that are not to be bold.', :last_crawl_status => IndexedDocument::OK_STATUS)
      IndexedDocument.reindex
      Sunspot.commit
    end

    context "when the title or description have matches to the query searched" do
      before do
        @search = Search.new(:query => 'highlight', :affiliate => @affiliate)
        @search.run
      end

      it "should highlight in Bing-style any matches" do
        @search.results.first['title'].should =~ /\xEE\x80\x80/
        @search.results.first['title'].should =~ /\xEE\x80\x81/
        @search.results.first['content'].should =~ /\xEE\x80\x80/
        @search.results.first['content'].should =~ /\xEE\x80\x81/
      end
    end

    context "when the title or description doesn't match the keyword queried" do
      before do
        @search = Search.new(:query => 'bold', :affiliate => @affiliate)
        @search.run
      end

      it "should not highlight anything" do
        @search.results.first['title'].should_not =~ /\xEE\x80\x80/
        @search.results.first['title'].should_not =~ /\xEE\x80\x81/
        @search.results.first['content'].should_not =~ /\xEE\x80\x80/
        @search.results.first['content'].should_not =~ /\xEE\x80\x81/
      end
    end
  end

  describe "#url_is_excluded(url)" do
    context "when an URL is unparseable" do
      let(:url) { "http://water.weather.gov/ahps2/hydrograph.php?wfo=lzk&gage=bkra4&view=1,1,1,1,1,1,1,1\"" }

      it "should not fail, and not exclude the url" do
        search = Search.new(:query => 'bold', :affiliate => @affiliate)
        search.send(:url_is_excluded,url).should be_false
      end
    end
  end
end
