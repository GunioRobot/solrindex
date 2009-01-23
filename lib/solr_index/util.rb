module SolrIndex
  module Util

    def self.parse_range(str)
      case str.to_s.strip
      when /^([\d\.]+)\+$/: "[#{$1} TO *]"
      when /^([\d\.]+)/: 	"[0 TO #{$1}]"
      else str.to_s.gsub(/[^\d\.]/,'')
      end
    end

  end
end