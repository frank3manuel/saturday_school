class SubjectsController < ApplicationController
  before_action :set_subject, only: %i[show edit update destroy]

  def index
    @subjects = current_user.subjects.to_a
    # Build the blank form object without polluting @subjects (association#new
    # would append the unsaved record to the loaded collection).
    @subject = Subject.new
  end

  def show
    @lessons = @subject.lessons.to_a
    # Build the blank form object without polluting @lessons (association#new
    # would append the unsaved record to the loaded collection).
    @lesson = Lesson.new(subject: @subject)
  end

  def new
    @subject = current_user.subjects.new
  end

  def edit
  end

  def create
    @subject = current_user.subjects.new(subject_params)

    if @subject.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @subject, notice: "Subject created." }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @subject.update(subject_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @subject, notice: "Subject updated." }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @subject.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to subjects_path, notice: "Subject deleted." }
    end
  end

  private

  # Always start from the association so another user's subject is simply not
  # found → 404 (plan §8.3). Never `Subject.find`.
  def set_subject
    @subject = current_user.subjects.find(params[:id])
  end

  def subject_params
    params.require(:subject).permit(:name, :description, :position)
  end
end
