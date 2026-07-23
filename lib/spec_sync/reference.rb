module SpecSync
  class Reference
    PATTERN = /\A(S-\d{2}):(AC-\d+)\z/

    attr_reader :spec_id, :criterion_id

    def self.parse(value)
      match = PATTERN.match(value.to_s.strip)
      raise ArgumentError, "Invalid criterion reference: #{value.inspect}" unless match

      new(spec_id: match[1], criterion_id: match[2])
    end

    def initialize(spec_id:, criterion_id:)
      @spec_id = spec_id
      @criterion_id = criterion_id
    end

    def to_s
      "#{spec_id}:#{criterion_id}"
    end

    def ==(other)
      other.is_a?(Reference) && other.to_s == to_s
    end
    alias eql? ==

    def hash
      to_s.hash
    end
  end
end
