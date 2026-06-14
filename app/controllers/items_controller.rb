class ItemsController < ApplicationController
  before_action :set_lesson, only: %i[new create]
  before_action :set_item, only: %i[edit update destroy]

  def new
    @item = @lesson.items.new
  end

  def edit
    respond_to do |format|
      # Swap the item's table row for an inline edit form.
      format.turbo_stream
      format.html # full-page edit fallback
    end
  end

  def create
    @item = @lesson.items.new(item_params)

    if @item.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @item.lesson, notice: "Item created." }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @item.update(item_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @item.lesson, notice: "Item updated." }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    lesson = @item.lesson
    @item.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to lesson, notice: "Item deleted." }
    end
  end

  private

  # Owner-scoped lookups (plan §8.3): items/lessons are reached only through the
  # current user's chain, so another user's records 404.
  def set_lesson
    @lesson = current_user.lessons.find(params[:lesson_id])
  end

  def set_item
    @item = current_user.items.find(params[:id])
  end

  def item_params
    params.require(:item).permit(:prompt, :answer, :item_type, :suspended)
  end
end
