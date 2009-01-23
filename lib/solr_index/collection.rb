module SolrIndex
  # Basic wrapper around WillPaginate::Collection, but with added field for solr_results
  class Collection < WillPaginate::Collection
    attr_accessor :solr_results, :original_query

    def self.empty
      new(1, 10, 0)
    end
  end
end
