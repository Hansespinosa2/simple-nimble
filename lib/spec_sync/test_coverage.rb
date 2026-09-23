require "ripper"

module SpecSync
  module TestCoverage
    REFERENCE_PATTERN = /S-\d{2}:AC-\d+/

    module_function

    def references_in(source)
      comments = Ripper.lex(source).filter_map do |_position, token_type, token, _state|
        token if token_type == :on_comment && token.match?(/\A#\s*S-\d{2}:AC-/)
      end

      comments.join.scan(REFERENCE_PATTERN).uniq
    end
  end
end
