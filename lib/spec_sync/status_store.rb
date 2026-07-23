require "yaml"

module SpecSync
  class StatusStore
    ALLOWED_STATUSES = %w[todo in_progress blocked].freeze

    attr_reader :path

    def initialize(path: Rails.root.join("specs/implementation_status.yml"))
      @path = Pathname(path)
    end

    def manual_status(reference)
      normalized_state = states.fetch("criteria", {}).fetch(reference.to_s, nil)
      return nil if normalized_state.nil?

      normalized_state.fetch("status")
    end

    def note(reference)
      normalized_state = states.fetch("criteria", {}).fetch(reference.to_s, nil)
      normalized_state&.fetch("notes", nil)
    end

    def update(reference:, status:, notes: nil, timestamp: Time.current.iso8601)
      normalized_status = status.to_s.strip
      unless ALLOWED_STATUSES.include?(normalized_status)
        raise ArgumentError, "Status must be one of: #{ALLOWED_STATUSES.join(', ')}"
      end

      payload = states
      payload["criteria"] ||= {}

      if normalized_status == "todo"
        payload["criteria"].delete(reference.to_s)
      else
        payload["criteria"][reference.to_s] = {
          "status" => normalized_status,
          "updated_at" => timestamp
        }
        payload["criteria"][reference.to_s]["notes"] = notes.to_s.strip unless notes.to_s.strip.empty?
      end

      write(payload)
    end

    def validate!(valid_references:)
      invalid_states = states.fetch("criteria", {}).each_with_object([]) do |(key, value), errors|
        errors << "Unknown criterion reference in status store: #{key}" unless valid_references.include?(key)

        status = value.fetch("status", nil)
        next if ALLOWED_STATUSES.include?(status)

        errors << "Unsupported manual status for #{key}: #{status.inspect}"
      end

      raise invalid_states.join("\n") if invalid_states.any?
    end

    private

    def states
      @states ||= begin
        if path.exist?
          YAML.safe_load(path.read, permitted_classes: [], aliases: false) || {}
        else
          {}
        end
      end
    end

    def write(payload)
      @states = payload
      path.dirname.mkpath
      path.write(payload.to_yaml)
    end
  end
end
