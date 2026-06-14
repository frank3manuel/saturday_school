class LessonsController < ApplicationController
  before_action :set_subject, only: %i[new create]
  before_action :set_lesson, only: %i[show edit update destroy]

  def show
    @items = @lesson.items.to_a
    # Honest display stage per item (plan §3), computed in bulk to avoid an
    # N+1 over the table: one grouped query for the longest survived gap.
    @stages = MasteryStage.for_items(@items)
    # Build the blank form object without polluting @items.
    @item = Item.new(lesson: @lesson)
  end

  def new
    @lesson = @subject.lessons.new
  end

  def edit
  end

  def create
    @lesson = @subject.lessons.new(lesson_params)

    if @lesson.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @lesson, notice: "Lesson created." }
      end
    else
      # Re-render just the inline new-lesson form frame with errors.
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @lesson.update(lesson_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @lesson, notice: "Lesson updated." }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    subject = @lesson.subject
    @lesson.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to subject, notice: "Lesson deleted." }
    end
  end

  private

  # Owner-scoped lookups (plan §8.3): a subject/lesson belonging to another user
  # is unreachable through the association → 404.
  def set_subject
    @subject = current_user.subjects.find(params[:subject_id])
  end

  def set_lesson
    @lesson = current_user.lessons.find(params[:id])
  end

  def lesson_params
    params.require(:lesson).permit(:title, :body, :position)
  end
end
