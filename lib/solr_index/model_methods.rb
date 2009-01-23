module SolrIndex
  module DefinitionMethod

    def index_fields(fields={})
      cattr_accessor :indexed_fields
      SolrIndex.register(self)
      self.indexed_fields = HashWithIndifferentAccess.new(fields)

      include SolrIndex::InstanceMethods
      extend  SolrIndex::ClassMethods

    end

    def index_conditions(conditions={})
      cattr_accessor :indexed_conditions
      self.indexed_conditions = conditions
    end

  end

  module ClassMethods

    def indexed_field_name(name)
      suffix, fields = self.indexed_fields.detect {|suffix, fields| fields.include?(name) }
      suffix && "#{name}_#{suffix}".to_sym
    rescue
      raise unless SolrIndex.catch_search_errors
    end


    def rebuild_index(limit=500)
      i = 0
      while i <= self.count
        SolrIndex.connection.add(find(:all, {:limit => limit, :offset => i}.merge(self.indexed_conditions)).map {|d| d.to_solr_document })
        i += limit
      end
      SolrIndex.connection.commit
    rescue
      raise unless SolrIndex.catch_search_errors
    end

  end

  module InstanceMethods

    # TODO: Refactor out concern
    def commit_to_index
      delete_from_index
      SolrIndex.connection.add(self.to_solr_document)
      SolrIndex.connection.commit
    rescue
      raise unless SolrIndex.catch_search_errors
    end

    # TODO: Refactor out concern
    def delete_from_index
      SolrIndex.connection.delete("#{self.class.to_s}_#{self.id}")
      SolrIndex.connection.commit
    rescue
      raise unless SolrIndex.catch_search_errors
    end

    # TODO: refactor
    def to_solr_document
      doc = Solr::Document.new(:id => "#{self.class.to_s}_#{self.id}", :ar_class_string => self.class.to_s)
      self.class.indexed_fields.each do |field_type, fields|
        fields.each do |method|
          if self.respond_to?("#{method}_for_index")
            value = self.send("#{method}_for_index")
          else
            value = self.send(method.to_sym)
          end
          if value.is_a?(Array)
            value.each do |v|
              doc << { self.class.indexed_field_name(method).to_sym => v }
            end
          elsif value.present?
            doc[self.class.indexed_field_name(method)] = self.class.indexed_field_name(method).to_s =~ /range/ ? value.to_f : value
          end
        end
      end
      doc
    end

  end
end
