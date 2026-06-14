import { Controller } from "@hotwired/stimulus"

// Quiz card interactions (plan §9, §10): reveal the answer (whole-card tap or
// Space), then 3-way self-grade (click or keys 1/2/3). Captures response
// latency passively (no visible timer) and submits the grade, which Turbo
// auto-advances to the next card by swapping only this frame.
export default class extends Controller {
  static targets = [
    "card", "answer", "revealHint", "grades",
    "form", "grade", "latency", "liveRegion"
  ]
  static classes = ["revealed"]

  connect() {
    this.revealed = false
    this.shownAt = performance.now() // start the passive latency timer
    document.addEventListener("keydown", this.onKeydown)
    // Publish a readiness flag: interactions (reveal/grade) only work once this
    // controller has connected. System tests wait on this before clicking, so a
    // click can't be dropped before Stimulus wires up the freshly-swapped card.
    this.element.setAttribute("data-quiz-ready", "true")
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  reveal() {
    if (this.revealed) return
    this.revealed = true

    this.answerTarget.hidden = false
    this.gradesTarget.hidden = false
    if (this.hasRevealHintTarget) this.revealHintTarget.hidden = true
    if (this.hasRevealedClass) this.element.classList.add(this.revealedClass)
    this.cardTarget.setAttribute("aria-expanded", "true")

    // Announce the reveal for screen readers (plan §9 a11y).
    if (this.hasLiveRegionTarget) this.liveRegionTarget.textContent = "Answer shown"
  }

  // Enter/Space on the focused card reveals it (ARIA button semantics).
  cardKeydown(event) {
    if (event.key === "Enter" || event.code === "Space" || event.key === " ") {
      event.preventDefault()
      this.reveal()
    }
  }

  // grade is triggered by a button carrying data-grade="missed|hard|good".
  grade(event) {
    if (!this.revealed) return
    const value = event.currentTarget.dataset.grade
    this.submitGrade(value)
  }

  submitGrade(value) {
    this.gradeTarget.value = value
    this.latencyTarget.value = Math.round(performance.now() - this.shownAt)
    this.formTarget.requestSubmit()
  }

  // Keyboard: Space reveals; 1/2/3 grade once revealed. Arrow-bound so `this`
  // is the controller when used as a document listener.
  onKeydown = (event) => {
    // Don't hijack typing in inputs/textareas.
    const tag = event.target.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || event.metaKey || event.ctrlKey) return

    if (!this.revealed && (event.code === "Space" || event.key === " ")) {
      event.preventDefault()
      this.reveal()
      return
    }

    if (this.revealed) {
      const map = { "1": "missed", "2": "hard", "3": "good" }
      const grade = map[event.key]
      if (grade) {
        event.preventDefault()
        this.submitGrade(grade)
      }
    }
  }
}
