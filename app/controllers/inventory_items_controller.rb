class InventoryItemsController < ApplicationController
  before_action :require_account
  before_action :set_character
  before_action :set_inventory_item, only: %i[update destroy]

  def create
    @inventory_item = @character.inventory_items.new(inventory_item_params)

    if @inventory_item.save
      @character.record_revision!(
        event_type: "inventory_update",
        summary: "Added #{@inventory_item.name} (#{@inventory_item.slots} inventory slots)",
        from_level: @character.level,
        to_level: @character.level
      )
      redirect_to @character, notice: "#{@inventory_item.name} added to inventory."
    else
      redirect_to @character, alert: @inventory_item.errors.full_messages.to_sentence
    end
  end

  def update
    if @inventory_item.update(inventory_item_params)
      @character.record_revision!(
        event_type: "inventory_update",
        summary: "Updated #{@inventory_item.name} (#{@inventory_item.slots} inventory slots)",
        from_level: @character.level,
        to_level: @character.level
      )
      redirect_to @character, notice: "Inventory item updated."
    else
      redirect_to @character, alert: @inventory_item.errors.full_messages.to_sentence
    end
  end

  def destroy
    item_name = @inventory_item.name
    @inventory_item.destroy!
    @character.record_revision!(
      event_type: "inventory_update",
      summary: "Removed #{item_name} from inventory",
      from_level: @character.level,
      to_level: @character.level
    )
    redirect_to @character, notice: "#{item_name} removed from inventory."
  end

  private
    def set_character
      @character = current_account.characters.find(params.expect(:character_id))
    end

    def set_inventory_item
      @inventory_item = @character.inventory_items.find(params.expect(:id))
    end

    def inventory_item_params
      params.expect(inventory_item: [ :name, :slots, :equipped ])
    end
end
