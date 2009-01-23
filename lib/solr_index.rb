require 'solr_index/model_methods'
require 'solr_index/query_builder'
require 'solr_index/collection'
require 'solr_index/util'

module SolrIndex

  class SolrIndexError < StandardError
  end

  class EmptyQueryError < SolrIndexError
  end

  class InvalidQueryError < SolrIndexError
  end

  @conection = nil
  def self.connection
    @connection ||= Solr::Connection.new
  end

  @known_indexed_classes = []
  def self.register(klass)
    @known_indexed_classes.push(klass) unless @known_indexed_classes.include?(klass)
  end

  def self.searchable?(const)
    @known_indexed_classes.include?(const.to_s.classify.constantize)
  end

  @catch_search_errors = nil
  def self.catch_search_errors
    @catch_search_errors
  end

  def self.catch_search_errors=(val)
    @catch_search_errors = val
  end

  @return_all_on_blank = nil
  def self.return_all_on_blank
    @return_all_on_blank
  end

  def self.return_all_on_blank=(val)
    @return_all_on_blank = val
  end

  def self.query(query, options={})
    if query.blank? && self.return_all_on_blank
      query = 'id:[0 TO *]'
    end
    connection.query(query, options)
  end

  def self.delete_all
    connection.delete_by_query("id:[0 TO *]")
    connection.commit
  end

  def self.rebuild_all
    delete_all
    @known_indexed_classes.each do |klass|
      klass.rebuild_index
    end
    connection.commit
    connection.optimize
  end

  def extract_search_options(args)
    options = args.extract_options!
    query = args.shift
    raise(InvalidQueryError, "Incorrect arguments to #search") unless query.is_a?(String)
    [query, options]
  end

  def self.search(*args)

    if block_given?
      query = QueryBuilder.new
      yield(query)
      options = args.extract_options!
      options.merge!(:page => query.page, :per_page => query.per_page, :sort => query.sort, :no_db => query.no_db)
    else
      query, options = extract_search_options(args)
    end

    no_db = options.delete(:no_db)

    finder_options = options.delete(:find) || {}

    rows  = options.delete(:per_page) || 10
    start = options.delete(:page)
    sort  = options.delete(:sort)
    options[:sort] = sort unless sort.blank?
    options[:rows] = rows if rows
    options[:start] = (rows * ((start || 1) - 1)) if start

    results = self.query(query.to_s, options.merge(:field_list => ['id', 'ar_class_string', 'score']))

    ooo_records, records = [], nil
    ids_for_class = {}

    # Grab all of the ids
    results.each do |doc|
      klass = doc['ar_class_string']
      ids_for_class[klass] ||= []
      ids_for_class[klass] << doc['id'][/_(\d+)$/, 1]
    end

    unless no_db

      ids_for_class.each do |klass,ids|
        ooo_records += klass.classify.constantize.find(ids, finder_options)
      end

      # Reassemble the records in order.
      records = results.map {|doc| ooo_records.detect {|r| doc['id'] == "#{r.class}_#{r.id}" }}
    end


    SolrIndex::Collection.create(start || 1, rows || 10, results.total_hits.to_i) do |page|
      page.solr_results = results
      page.replace(records || results.hits)
      page.original_query = query.respond_to?(:supplied_conditions) ? query.supplied_conditions : query.to_s
    end
  rescue EmptyQueryError, InvalidQueryError, Errno::ECONNREFUSED, ActiveRecord::RecordNotFound
    self.catch_search_errors ? Collection.empty : raise
  end

  def self.raw_results
    query = QueryBuilder.new
    yield(query)
    self.query(query.to_s, :field_list => ['id', 'ar_class_string', 'score'], :rows => '1000')
  end
end
