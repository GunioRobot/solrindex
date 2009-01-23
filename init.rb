require 'solr'
require 'solr_index'

ActiveRecord::Base.extend SolrIndex::DefinitionMethod