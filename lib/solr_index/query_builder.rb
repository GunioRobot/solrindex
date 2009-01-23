module SolrIndex

  class QueryBuilder
    cattr_accessor :allow_empty_query
    attr_accessor  :query_parts, :sort, :page, :per_page, :model, :boolean, :no_db

    def initialize(query="")
      self.query_parts = []
      self.sort_parts = []
      self.add query
    end

    def model=(model)
      @model = model.to_s.constantize
    end

    def <<(query)
      self.add query
    end

    def add(value)
      unless value.blank?
        self.query_parts << value
      end
    end

    # accepts a number of sorting options that mimic
    # sql order clauses
    def sort=(val)
      case val
      when String
        @sort = parse_sort_string(val)
      when Array
        @sort = val.first.is_a?(String) ? parse_sort_string(val.join(',')) : val
      when Hash
        @sort = [val]
      end
    end

    def parse_sort_string(val)
      val.split(',').map {|s| { s[/(\w+)\s+(asc|desc)/i,1] => $2 =~ /desc/ ? :descending : :ascending} }
    end

    def sort
      return nil if @sort.blank?
      if self.model
        @sort.map {|h| {self.model.indexed_field_name(h.keys.first.to_sym) => h.values.first} }
      else
        @sort
      end
    end

    def page
      @page ? @page.to_i : 1
    end

    def method_missing(sym, *args)
      # ok, ugly. basically looks for an element that is _not_ blank
      return unless args.flatten.detect {|value| !value.blank? }
      sym = sym.to_s
      if sym =~ /=$/
        name = sym[/^(.*)=$/,1]
        if self.model
          name = self.model.indexed_field_name(name.to_sym) || name
        end
        value = args.first
        case value
        when String
          if value.first == "["
            self.add "#{name}:#{value}"
          else
            self.add "#{name}:\"#{value}\""
          end
        when Array
          set = value.map {|v| "#{name}:\"#{v}\"" unless v.blank? }
          self.add "(#{set.join(' OR ')})"
        when Range
          self.add "#{name}:[#{value.first} TO #{value.last}]" unless value.last == 0
        end
      end

    end

    def validate_query
      if self.query_parts.join(" ").blank? && (self.allow_empty_query.blank? && self.class.allow_empty_query.blank?)
        raise EmptyQueryError, "QueryBuilder was unable to construct a query"
      end
    end

    def supplied_conditions
      self.query_parts.join(" #{self.boolean} ") unless self.query_parts.blank?
    end

    def class_condition
      "ar_class_string:#{self.model.to_s}" unless self.model.blank?
    end

    def sort_string
      self.sort_parts.blank? ? '' : ';' + sort_parts.join(',')
    end

    def to_s
      validate_query
      [class_condition, supplied_conditions].compact.join(" AND ") + sort_string
    end

  end
end