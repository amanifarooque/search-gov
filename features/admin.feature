Feature:  Administration
  Scenario: Visiting the admin home page as an admin
    Given I am logged in with email "affiliate_admin@fixtures.org" and password "admin"
    When I go to the admin home page
    Then I should see the browser page titled "Super Admin"
    And I should see "Super Admin" in the page header
    And I should see "affiliate_admin@fixtures.org"
    And I should see "My Account"
    And I should see "Sign Out"

    When I follow "Super Admin" in the main navigation bar
    Then I should be on the admin home page

    When I follow "Sign Out"
    Then I should be on the login page

  Scenario: Visiting the admin home page as an admin who is also an affiliate
    Given I am logged in with email "affiliate_admin@fixtures.org" and password "admin"
    And "affiliate_admin@fixtures.org" is an affiliate
    When I go to the admin home page
    Then I should see "Super Admin" in the user menu
    And I should see "Admin Center" in the user menu

  Scenario: Visiting the affiliate admin page as an admin
    Given I am logged in with email "affiliate_admin@fixtures.org" and password "admin"
    And the following Affiliates exist:
      | display_name | name       | contact_email | contact_name | website                |
      | agency site  | agency.gov | one@foo.gov   | One Foo      | http://beta.agency.gov |
    And the following site domains exist for the affiliate agency.gov:
      | domain               | site_name      |
      | www1.agency-site.gov | Agency Website |
    When I go to the admin home page
    And I follow "Sites" within ".main"
    Then I should see the following breadcrumbs: Super Admin > Sites
    And I should see "Display name"
    And I should see "Site Handle (visible to searchers in the URL)"
    And I should see "agency site"
    And I should see "agency.gov"
    And I should see "www1.agency-site.gov"
    And I should see a link to "beta.agency.gov" with url for "http://beta.agency.gov"

    When I follow "www1.agency-site.gov"
    Then I should see "Agency Website"

  Scenario: Visiting the users admin page as an admin
    Given I am logged in with email "affiliate_admin@fixtures.org" and password "admin"
    When I go to the admin home page
    And I follow "Users" within ".main"
    Then I should be on the users admin page
    And I should see the following breadcrumbs: Super Admin > Users
    When I follow "Edit" within the first scaffold row
    Then the "Default affiliate" select field should contain 1 option

  Scenario: Visiting the SAYT Filters admin page as an admin
    Given I am logged in with email "affiliate_admin@fixtures.org" and password "admin"
    When I go to the admin home page
    And I follow "Filters" within ".main"
    Then I should be on the sayt filters admin page
    And I should see the following breadcrumbs: Super Admin > Type Ahead Filters

  Scenario: Viewing Boosted Content (both affiliate and Search.USA.gov)
    Given I am logged in with email "affiliate_admin@fixtures.org" and password "admin"
    And the following Affiliates exist:
      | display_name | name    | contact_email | contact_name |
      | bar site     | bar.gov | aff@bar.gov   | John Bar     |
    And the following Boosted Content entries exist for the affiliate "bar.gov"
      | title              | url                    | description                        |
      | Bar Emergency Page | http://www.bar.gov/911 | This should not show up in results |
    When I go to the admin home page
    And I follow "Best Bets: Text"
    Then I should see the following breadcrumbs: Super Admin > Best Bets: Text
    And I should see "Bar Emergency Page"
    And I should not see "Our Emergency Page"

  Scenario: Viewing monthly reports for affiliates
    Given I am logged in with email "affiliate_admin@fixtures.org" and password "admin"
    And the following Affiliates exist:
      | display_name  | name        | contact_email | contact_name |
      | agency site   | agency.gov  | one@foo.gov   | One Foo      |
      | agency site 2 | agency2.gov | two@foo.gov   | Two Foo      |
    And the following DailyUsageStats exist for each day in "2012-03"
     | total_queries | affiliate   |
     | 100           | agency.gov  |
     | 200           | agency2.gov |
    When I go to the admin home page
    And I follow "Monthly Reports"
    Then I should not see "Total Queries: 300"
    And I should not see "Total Clicks: 300"

    When I select "agency.gov" from "Affiliate"
    And I select "March 2012" as the report date
    And I press "Submit"
    Then I should see "Total Queries: 3,100"

    When I select "agency2.gov" from "Affiliate"
    And I press "Submit"
    Then I should see "Total Queries: 6,200"

  Scenario: Viewing affiliate reports
    Given I am logged in with email "affiliate_admin@fixtures.org" and password "admin"
    And the following Affiliates exist:
      | display_name  | name        | contact_email | contact_name |
      | agency site   | agency.gov  | one@foo.gov   | One Foo      |
      | agency site 2 | agency2.gov | two@foo.gov   | Two Foo      |
    And the following DailyUsageStats exists for each day in yesterday's month
      | total_queries | affiliate   |
      | 300           | agency.gov  |
      | 400           | agency2.gov |
    When I go to the admin home page
    And I follow "Customer Reports"
    Then I should see a total for "agency.gov" with a total of "300" per day
    And I should see a total for "agency2.gov" with a total of "400" per day

    Given the following DailyUsageStats exist for each day in "2012-04"
      | total_queries | affiliate   |
      | 100           | agency.gov  |
      | 200           | agency2.gov |
    When I select "April 2012" as the report date
    And I press "Submit"
    Then I should see a total for "agency.gov" with a total of "3000"
    Then I should see a total for "agency2.gov" with a total of "6000"

  Scenario: Comparing Search Results
    Given I am logged in with email "affiliate_admin@fixtures.org" and password "admin"
    And the following Affiliates exist:
      | display_name  | name     | contact_email | contact_name |
      | agency site   | aff.gov  | one@foo.gov   | One Foo      |
      | agency site 2 | aff2.gov | two@foo.gov   | Two Foo      |
    And the following site domains exist for the affiliate aff.gov:
      | domain               | site_name      |
      | aff.gov              | Agency Website |
    And the following site domains exist for the affiliate aff2.gov:
      | domain              | site_name      |
      | aff.gov             | Agency2 Website |
    And the following IndexedDocuments exist:
      | title                   | description                     | url                          | affiliate | last_crawled_at | last_crawl_status |
      | Space Suit America      | description for space suit item | http://aff.gov//space-suit1  | aff.gov   | 11/02/2011      | OK                |
      | America Suit Evolution  | description for space suit item | http://aff.gov//space-suit2  | aff.gov   | 11/02/2011      | OK                |
      | Space America Evolution | description for space suit item | http://aff.gov//space-suit3  | aff.gov   | 11/02/2011      | OK                |
      | America IN SPACE        | description for space suit item | http://aff.gov//space-suit1  | aff2.gov  | 11/02/2011      | OK                |
    When I go to the admin home page
    And I follow "Compare Search Results"
    Then I should not see "Bing Results"
    And I should not see "ODIE Results"

    When I fill in "query" with "america"
    When I select "aff.gov" from "Affiliate"
    And I press "Search"
    Then I should see "Bing Results"
    And I should see "ODIE Results"
    And I should see "Space Suit America"
    And I should not see "America IN SPACE"

  Scenario: Visiting the active scaffold pages
    Given I am logged in with email "affiliate_admin@fixtures.org" and password "admin"

    When I go to the admin home page
    And I follow "Users"
    And I should see the following breadcrumbs: Super Admin > Users

    When I go to the admin home page
    And I follow "Filters"
    Then I should see the following breadcrumbs: Super Admin > Type Ahead Filters

    When I go to the admin home page
    And I follow "Suggestions"
    Then I should see the following breadcrumbs: Super Admin > Type Ahead Suggestions

    When I go to the admin home page
    And I follow "Misspellings"
    Then I should see the following breadcrumbs: Super Admin > Type Ahead Misspellings

    When I go to the admin home page
    And I follow "Best Bets: Text"
    Then I should see the following breadcrumbs: Super Admin > Best Bets: Text

    When I go to the admin home page
    And I follow "Collections"
    Then I should see the following breadcrumbs: Super Admin > Collections

    When I go to the admin home page
    And I follow "Superfresh Urls"
    Then I should see the following breadcrumbs: Super Admin > SuperfreshUrls

    When I go to the admin home page
    And I follow "Superfresh Bulk Upload"
    Then I should see the following breadcrumbs: Super Admin > Superfresh Bulk Upload

    When I go to the admin home page
    And I follow "Agencies"
    Then I should see the following breadcrumbs: Super Admin > Agencies

    When I go to the admin home page
    And I follow "Blocked Queries"
    Then I should see the following breadcrumbs: Super Admin > Logfile Blocked Queries

    When I go to the admin home page
    And I follow "Blocked IPs"
    Then I should see the following breadcrumbs: Super Admin > Logfile Blocked IPs

    When I go to the admin home page
    And I follow "Blocked Class Cs"
    Then I should see the following breadcrumbs: Super Admin > Logfile Blocked Class Cs

    When I go to the admin home page
    And I follow "Whitelisted Class Cs"
    Then I should see the following breadcrumbs: Super Admin > Logfile Whitelisted Class Cs

    When I go to the admin home page
    And I follow "Blocked Regexps"
    Then I should see the following breadcrumbs: Super Admin > Logfile Blocked Regexps

    When I go to the admin home page
    And I follow "Blocked User Agents"
    Then I should see the following breadcrumbs: Super Admin > Logfile Blocked User Agents

    When I go to the admin home page
    And I follow "Modules"
    Then I should see the following breadcrumbs: Super Admin > Modules

    When I go to the admin home page
    And I follow "Features" in the Super Admin page
    Then I should see the following breadcrumbs: Super Admin > Features

    When I go to the admin home page
    And I follow "Statuses" in the Super Admin page
    Then I should see the following breadcrumbs: Super Admin > Site Statuses
    And I should see "active"
    And I should see "inactive"

    When I go to the admin home page
    And I follow "Tags" in the Super Admin page
    Then I should see the following breadcrumbs: Super Admin > Site Tags
    And I should see "bad code"
    And I should see "case study"

    When I go to the admin home page
    And I follow "Customer Scopes"
    Then I should see the following breadcrumbs: Super Admin > Customer Scopes

    When I go to the admin home page
    And I follow "Customer Catalog Prefix Whitelist"
    Then I should see the following breadcrumbs: Super Admin > Customer Catalog Prefix Whitelist

    When I go to the admin home page
    And I follow "Help Links"
    Then I should see the following breadcrumbs: Super Admin > HelpLinks

    When I go to the admin home page
    And I follow "Email Templates"
    Then I should see the following breadcrumbs: Super Admin > EmailTemplates

    When I go to the admin home page
    And I follow "System Alerts"
    Then I should see the following breadcrumbs: Super Admin > System Alerts

  Scenario: Adding help link
    Given I am logged in with email "affiliate_admin@fixtures.org" and password "admin"
    When I go to the admin home page
    And I follow "Help Link"
    And I follow "Create"
    And I fill in "Help page url" with "http://usasearch.howto.gov/edit_rss"
    And I fill in "Request path" with "http://localhost/affiliates/1/rss_feed/2/edit/?m=false"
    And I press "Create"
    Then I should see the following table rows:
      | Help page url                       | Request path              |
      | http://usasearch.howto.gov/edit_rss | /affiliates/rss_feed/edit |
