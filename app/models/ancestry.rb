class Ancestry < ApplicationRecord
  # Structured rules-canon slice (spec 02): seeded with 2 of the 19 Nimble
  # ancestries for a minimal-but-real vertical slice.
  has_many :characters, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :size, presence: true
end
