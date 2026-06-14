import { Controller } from "@hotwired/stimulus"

// Toggles a password field between hidden and visible without breaking browser
// autofill (plan §10): the toggle is type="button", tracks state via
// aria-pressed, and only flips the input's `type`.
export default class extends Controller {
  static targets = ["input", "toggle"]

  toggle() {
    const showing = this.inputTarget.type === "text"
    this.inputTarget.type = showing ? "password" : "text"
    this.toggleTarget.setAttribute("aria-pressed", String(!showing))
    this.toggleTarget.textContent = showing ? "Show" : "Hide"
  }
}
