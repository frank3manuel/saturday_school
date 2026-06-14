require "test_helper"

class ItemsControllerTest < ActionDispatch::IntegrationTest
  test "create nests the item under its lesson" do
    assert_difference -> { lessons(:algebra).items.count }, 1 do
      post lesson_items_path(lessons(:algebra)),
           params: { item: { prompt: "Q?", answer: "A" } }
    end
    assert_response :redirect
  end

  test "create with turbo_stream appends a row" do
    post lesson_items_path(lessons(:algebra)),
         params: { item: { prompt: "Q?", answer: "A" } },
         as: :turbo_stream
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
  end

  test "create with invalid params re-renders" do
    assert_no_difference -> { Item.count } do
      post lesson_items_path(lessons(:algebra)),
           params: { item: { prompt: "", answer: "" } },
           as: :turbo_stream
    end
    assert_response :unprocessable_entity
  end

  test "edit returns a turbo_stream row swap when requested" do
    get edit_item_path(items(:due_item)), as: :turbo_stream
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
  end

  test "update changes the item" do
    patch item_path(items(:due_item)), params: { item: { answer: "five" } }
    assert_equal "five", items(:due_item).reload.answer
  end

  test "destroy removes the item" do
    assert_difference -> { Item.count }, -1 do
      delete item_path(items(:due_item))
    end
  end

  test "cannot mass-assign SRS state through item params" do
    post lesson_items_path(lessons(:algebra)),
         params: { item: { prompt: "Q?", answer: "A", streak: 99, state: "mastered" } }
    item = Item.order(:id).last
    assert_equal 0, item.streak
    assert_equal "learning", item.state
  end
end
