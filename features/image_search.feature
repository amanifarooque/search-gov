Feature: Image search
  In order to get government-related images
  As a site visitor
  I want to search for images

  Scenario: Image search landing page
    Given the following Affiliates exist:
      | display_name | name   | contact_email | contact_name | header         | search_results_page_title           |
      | USA.gov      | usagov | aff@bar.gov   | John Bar     | USA.gov Header | {Query} - {SiteName} Search Results |
    When I am on the homepage
    And I follow "Images" in the search navigation
    Then I should be on the images page
    And I should see the browser page titled "Search.USA.gov Images"
    And I should not see "ROBOTS" meta tag
    And I should not see "Advanced Search"
    And I should see "Connect with USASearch" in the connect section
    And I should see a link to "Twitter" with url for "http://twitter.com/usasearch" in the connect section
    And I should see a link to "Mobile" with url for "http://m.usa.gov" in the connect section
    And I should see a link to "Our Blog" with url for "http://searchblog.usa.gov" in the connect section
    And I should see a link to "Share" with url for "http://www.addthis.com/bookmark.php" in the connect section

    When I fill in "query" with "White House"
    And I press "Search"
    Then I should see the browser page titled "White House - USA.gov Search Results"

    When I am on the homepage
    And I follow "Images" in the search navigation
    And I follow "USASearch Images Home"
    Then I should see the browser page titled "Search.USA.gov Images"

  Scenario: Visiting Spanish image search homepage
    Given the following Affiliates exist:
      | display_name    | name        | contact_email | contact_name | header                  | search_results_page_title                      |
      | GobiernoUSA.gov | gobiernousa | aff@bar.gov   | John Bar     | Gobierno.USA.gov Header | {Query} - {SiteName} resultados de la búsqueda |
    When I am on the Spanish homepage
    And I follow "Imágenes" in the search navigation
    Then I should see the browser page titled "Buscador.USA.gov Imágenes"
    And I should not see "ROBOTS" meta tag
    And I should not see "Búsqueda avanzada"
    And I should not see "Connect with USASearch"

    When I fill in "query" with "White House"
    And I press "Buscar"
    And I should see the browser page titled "White House - GobiernoUSA.gov resultados de la búsqueda"

    When I am on the Spanish homepage
    And I follow "Imágenes" in the search navigation
    And I follow "USASearch Images Home"
    Then I should see the browser page titled "Buscador.USA.gov Imágenes"

  Scenario: A unicode search
    Given the following Affiliates exist:
      | display_name | name   | contact_email | contact_name | header         | search_results_page_title           |
      | USA.gov      | usagov | aff@bar.gov   | John Bar     | USA.gov Header | {Query} - {SiteName} Search Results |
    When I am on the homepage
    And I follow "Images"
    When I fill in "query" with "البيت الأبيض"
    And I submit the search form
    Then I should see "البيت الأبيض"

  Scenario: Visiting other verticals from the image search homepage
    Given the following Affiliates exist:
      | display_name | name   | contact_email | contact_name | header         | search_results_page_title           |
      | USA.gov      | usagov | aff@bar.gov   | John Bar     | USA.gov Header | {Query} - {SiteName} Search Results |
    When I am on the images page
    And I follow "Web" in the search navigation
    Then I should be on the homepage
