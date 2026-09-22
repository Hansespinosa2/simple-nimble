namespace :spec_sync do
  desc "Show spec acceptance-criteria implementation status"
  task :status, [ :filter ] => :environment do |_task, args|
    tracker = SpecSync::Tracker.new
    tracker.validate!

    statuses = tracker.criterion_statuses(filter: args[:filter])
    grouped = statuses.group_by(&:spec_title)

    puts "Spec sync status"
    puts "================"
    puts

    if grouped.empty?
      puts "No matching specs found."
      next
    end

    grouped.each_value do |criteria|
      first = criteria.first
      puts "#{first.reference.spec_id} - #{first.spec_title} (spec status: #{first.spec_status})"
      puts "  Source: #{first.spec_path}"

      criteria.each do |criterion|
        puts "  - #{criterion.reference} [#{criterion.implementation_status}] #{criterion.type}"
        puts "    #{criterion.criterion}"
        puts "    Spec confidence: #{criterion.spec_confidence}"
        puts "    Manual state: #{criterion.manual_status}" if criterion.manual_status

        if criterion.commit_links.any?
          criterion.commit_links.first(3).each do |link|
            puts "    Commit: #{link.sha[0, 7]} #{link.summary}"
          end
          remaining = criterion.commit_links.length - 3
          puts "    ... #{remaining} more commit(s)" if remaining.positive?
        end
      end

      puts
    end
  end

  desc "Set a manual implementation status for an acceptance criterion"
  task :mark, [ :reference, :status, :notes ] => :environment do |_task, args|
    reference = SpecSync::Reference.parse(args[:reference])
    tracker = SpecSync::Tracker.new
    tracker.validate!

    unless tracker.criterion_statuses(filter: reference.to_s).any?
      abort "Unknown criterion reference: #{reference}"
    end

    SpecSync::StatusStore.new.update(reference:, status: args[:status], notes: args[:notes])
    puts "Updated #{reference} to #{args[:status]}"
  end

  desc "Validate the spec sync catalog, status store, and references"
  task validate: :environment do
    SpecSync::Tracker.new.validate!
    puts "Spec sync configuration is valid."
  end

  desc "Generate a test-to-acceptance-criteria coverage report"
  task coverage: :environment do
    tracker = SpecSync::Tracker.new
    tracker.validate!
    test_files = Dir[Rails.root.join("test/**/*_test.rb")].sort
    references_by_file = test_files.to_h do |path|
      references = File.read(path).scan(/S-\d{2}:AC-\d+/).uniq
      [ Pathname(path).relative_path_from(Rails.root).to_s, references ]
    end
    files_by_reference = Hash.new { |hash, key| hash[key] = [] }
    references_by_file.each do |file, references|
      references.each { |reference| files_by_reference[reference] << file }
    end

    puts "Spec test coverage"
    puts "=================="
    puts
    tracker.criterion_statuses.each do |criterion|
      files = files_by_reference.fetch(criterion.reference.to_s, [])
      status = files.any? ? "covered" : "missing"
      puts "#{criterion.reference} [#{status}] #{criterion.criterion}"
      puts "  Tests: #{files.any? ? files.join(', ') : 'No tagged test file'}"
    end

    provisional_specs = Dir[Rails.root.join("specs/app/[0-9][0-9]-*.md")].select do |path|
      File.read(path).include?("[Unknown: TBD]")
    end
    puts
    puts "Provisional specs"
    puts "================="
    puts provisional_specs.any? ? provisional_specs.map { |path| Pathname(path).relative_path_from(Rails.root) } : "None"
  end
end
