require "test_helper"
require "tmpdir"

class SpecSyncStatusStoreTest < ActiveSupport::TestCase
  test "writes sparse manual states and removes todo entries" do
    Dir.mktmpdir do |dir|
      store = SpecSync::StatusStore.new(path: File.join(dir, "implementation_status.yml"))
      reference = SpecSync::Reference.parse("S-05:AC-1")

      store.update(reference:, status: "in_progress", notes: "Building the wizard")

      assert_equal "in_progress", store.manual_status(reference)
      assert_equal "Building the wizard", store.note(reference)

      store.update(reference:, status: "todo")

      assert_nil store.manual_status(reference)
    end
  end

  test "rejects unsupported manual statuses" do
    Dir.mktmpdir do |dir|
      store = SpecSync::StatusStore.new(path: File.join(dir, "implementation_status.yml"))

      error = assert_raises(ArgumentError) do
        store.update(reference: SpecSync::Reference.parse("S-05:AC-1"), status: "done")
      end

      assert_match(/Status must be one of/, error.message)
    end
  end
end
