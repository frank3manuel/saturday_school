# frozen_string_literal: true

# demo:load — seed a coherent, believable classroom demo (1 teacher, 3 students,
# 5 subjects × 5 lessons × 10 items = 250 items, one cohort with all three
# students enrolled and all 25 lessons assigned), with a realistic spread of SRS
# state so Today has due cards and Progress shows a full distribution.
#
# IDEMPOTENT + SCOPED. Every demo record hangs off a "@demo.test" account, so a
# re-run first destroys those accounts (and, via dependent: :destroy + DB
# cascades, all their subjects/lessons/items/review_states/attempts/cohorts/
# enrollments/assignments) and rebuilds from scratch. It never touches the seeded
# admin or any real account a user signed up with — only the demo.test users.
#
# Deterministic: no randomness. The spread is a fixed function of record indices
# and Time.current-relative offsets, so two runs produce the same demo.
#
# How the stages are made honest: the Progress dashboards (ProgressReport,
# CohortProgressReport) derive each item's display stage from the APPEND-ONLY
# attempt log — specifically the largest `interval_before` over its CORRECT
# attempts (see MasteryStage). The Today queue / forecast read the inline SRS
# columns (owner) and review_states rows (students). So for a stage to show up in
# BOTH places we write the SRS columns AND append one anchor correct attempt whose
# `interval_before` equals the gap that earns the stage. Everything stays mutually
# consistent with Srs::Scheduler's ladder.
namespace :demo do
  # The five display stages (MasteryStage::STAGES) expressed as a coherent bundle
  # of SRS column values + the attempt `interval_before` that earns the stage.
  #   :level         -> box (index into Srs::Scheduler::INTERVALS)
  #   :survived_days -> interval_before of the anchor correct attempt (the gap the
  #                     learner has been recalled across); nil == no correct
  #                     attempt at all, i.e. the New stage.
  STAGE_PROFILES = {
    new: {
      state: :learning, level: 0, streak: 0, repetitions: 0, lapses: 0,
      mastered: false, survived_days: nil
    },
    learning: {
      state: :review, level: 1, streak: 1, repetitions: 1, lapses: 0,
      mastered: false, survived_days: 0
    },
    young: {
      state: :review, level: 2, streak: 2, repetitions: 2, lapses: 0,
      mastered: false, survived_days: 1
    },
    maturing: {
      state: :mastered, level: 3, streak: 3, repetitions: 3, lapses: 0,
      mastered: true, survived_days: 7
    },
    durable: {
      state: :mastered, level: 5, streak: 5, repetitions: 6, lapses: 1,
      mastered: true, survived_days: 60
    }
  }.freeze

  # The ordered stages (new -> durable). Defined locally rather than referencing
  # MasteryStage::STAGES here, because this file is PARSED before the Rails
  # environment loads (the :environment prerequisite only runs at task-invoke
  # time). At runtime DemoLoader asserts this equals MasteryStage::STAGES.
  STAGES = %i[new learning young maturing durable].freeze

  DEMO_EMAIL_SUFFIX = "@demo.test"
  DEMO_PASSWORD = "password"

  ADMIN = { email: "admin#{DEMO_EMAIL_SUFFIX}", name: "Demo Admin" }.freeze
  TEACHER = { email: "teacher#{DEMO_EMAIL_SUFFIX}", name: "Demo Teacher" }.freeze
  STUDENTS = [
    { email: "ana#{DEMO_EMAIL_SUFFIX}" },
    { email: "ben#{DEMO_EMAIL_SUFFIX}" },
    { email: "cara#{DEMO_EMAIL_SUFFIX}" }
  ].freeze

  COHORT_NAME = "Demo Class 2026"

  desc "Seed (idempotently) a believable classroom demo scoped to @demo.test accounts"
  task load: :environment do
    DemoLoader.new.call
  end

  # A plain orchestrator (kept inside the task file so it doesn't leak into app/).
  class DemoLoader
    def initialize(now: Time.current)
      @now = now
      @today = now.to_date
    end

    def call
      # Guard: keep the local stage order in lockstep with the app's source of truth.
      unless STAGES == MasteryStage::STAGES
        raise "demo:load STAGES drifted from MasteryStage::STAGES"
      end

      ActiveRecord::Base.transaction do
        wipe_existing_demo!
        @admin    = create_admin
        @teacher  = create_teacher
        @students = create_students
        @subjects = create_subjects_lessons_items
        seed_owner_state!
        @cohort = create_cohort_with_enrollments
        assign_all_lessons!
        seed_student_state!
      end
      print_summary
    end

    private

    # --- Idempotency: clear ONLY the demo's own records -------------------
    # Destroy cohorts first (cohorts.teacher_id FK is on_delete: :restrict, so the
    # teacher can't be deleted while a cohort exists; the cohort cascade also clears
    # assignments whose assigned_by FK is :restrict). Then destroy the demo users,
    # whose dependent: :destroy + DB cascades take the rest (subjects -> lessons ->
    # items -> review_states/attempts, plus enrollments).
    def wipe_existing_demo!
      demo_users = User.where("email_address LIKE ?", "%#{DEMO_EMAIL_SUFFIX}")
      Cohort.where(teacher_id: demo_users.select(:id)).destroy_all
      demo_users.destroy_all
    end

    # --- Accounts ---------------------------------------------------------
    # The admin owns no learning content or cohorts — admins manage accounts,
    # roles, and the audit log, not the library. Just an account is enough to
    # sign in and reach the Admin area. It's wiped+recreated like every other
    # demo.test account, and since it owns nothing it deletes cleanly (no cohort
    # FK :restrict to order around, unlike the teacher).
    def create_admin
      User.create!(
        email_address: ADMIN[:email],
        password: DEMO_PASSWORD,
        role: "admin",
        verified_at: @now
      )
    end

    def create_teacher
      User.create!(
        email_address: TEACHER[:email],
        password: DEMO_PASSWORD,
        role: "teacher",
        verified_at: @now
      )
    end

    def create_students
      STUDENTS.map do |attrs|
        User.create!(
          email_address: attrs[:email],
          password: DEMO_PASSWORD,
          role: "student",
          verified_at: @now
        )
      end
    end

    # --- Content: 5 subjects x 5 lessons x 10 items = 250 items ----------
    def create_subjects_lessons_items
      CONTENT.each_with_index.map do |subject_data, s_index|
        subject = @teacher.subjects.create!(
          name: subject_data[:name],
          description: subject_data[:description],
          position: s_index
        )
        subject_data[:lessons].each_with_index do |lesson_data, l_index|
          lesson = subject.lessons.create!(
            title: lesson_data[:title],
            body: lesson_data[:body],
            position: l_index
          )
          lesson_data[:items].each do |prompt, answer|
            lesson.items.create!(prompt: prompt, answer: answer)
          end
        end
        subject
      end
    end

    # --- Owner SRS state: distribute the teacher's OWN items across stages -
    # Walk every item in a stable order and round-robin the five stages, so all
    # five appear and the due dates vary. The teacher reads inline columns.
    def seed_owner_state!
      teacher_items.each_with_index do |item, index|
        stage = STAGES[index % STAGES.size]
        apply_stage!(home: item, learner: @teacher, item: item, stage: stage, salt: index)
      end
    end

    def teacher_items
      Item.where(lesson_id: Lesson.where(subject_id: @subjects.map(&:id)).select(:id))
          .order(:lesson_id, :id)
    end

    # --- Cohort + enrollments --------------------------------------------
    def create_cohort_with_enrollments
      cohort = @teacher.taught_cohorts.create!(
        name: COHORT_NAME,
        description: "A demo class with three students and the full library assigned."
      )
      @students.each do |student|
        cohort.enrollments.create!(user: student, status: "active")
      end
      cohort
    end

    # --- Assign all 25 lessons through the real assignment path ----------
    # Creating each Assignment then eagerly materializing review_states for the
    # active enrollees, exactly as the M6 flow does (AssignmentEnroller).
    def assign_all_lessons!
      @subjects.each do |subject|
        subject.lessons.each do |lesson|
          assignment = @cohort.assignments.create!(
            lesson: lesson,
            assigner: @teacher
          )
          AssignmentEnroller.enroll_assignment(assignment)
        end
      end
    end

    # --- Student SRS state: distribute each student across all five stages,
    # and make the three students genuinely DIFFER (one ahead, one mid, one
    # behind) by giving each a different STAGE-WEIGHTING, not just a phase shift.
    # A pure rotation would leave all three with an identical 50/50/50/50/50
    # distribution; weighting changes the actual shape so the class-aggregate
    # progress shows three distinct profiles. -----------------------------------
    def seed_student_state!
      assigned_items = teacher_items.to_a
      @students.each_with_index do |student, s_index|
        plan = student_stage_plan(s_index, assigned_items.size)
        states = ReviewState.where(user_id: student.id).index_by(&:item_id)
        assigned_items.each_with_index do |item, i_index|
          stage = plan[i_index]
          home = states.fetch(item.id)
          apply_stage!(home: home, learner: student, item: item, stage: stage, salt: i_index + s_index)
        end
      end
    end

    # Per-student stage WEIGHTS (out of 10), giving three distinct learners:
    #   Ana  — ahead  : heavy maturing/durable, little new
    #   Ben  — middle : balanced
    #   Cara — behind : heavy new/learning, little durable
    # Indices align with STAGES (new, learning, young, maturing, durable).
    STUDENT_STAGE_WEIGHTS = [
      [ 1, 1, 2, 3, 3 ], # ahead
      [ 2, 2, 2, 2, 2 ], # middle
      [ 4, 3, 2, 1, 0 ]  # behind (no durable yet)
    ].freeze

    # Build a deterministic, fully-materialized array of `count` stages for a
    # student, with each stage appearing in proportion to its weight. Interleaved
    # (round-robin by stage) rather than blocked, so within any lesson the
    # student's items aren't all the same stage — the bars read believably.
    def student_stage_plan(student_index, count)
      weights = STUDENT_STAGE_WEIGHTS[student_index]
      total = weights.sum
      # How many items each stage gets, summing exactly to `count`.
      per_stage = weights.map { |w| (count * w) / total }
      per_stage[per_stage.index(per_stage.max)] += count - per_stage.sum # absorb rounding

      queues = STAGES.each_with_index.map { |stage, i| Array.new(per_stage[i], stage) }
      plan = []
      until queues.all?(&:empty?)
        queues.each { |q| plan << q.shift unless q.empty? }
      end
      plan
    end

    # --- The one place that writes a stage consistently ------------------
    # Writes the SRS columns onto `home` (an Item for the owner, a ReviewState for
    # a student) AND appends one anchor correct attempt (when the stage was earned
    # by surviving a gap) so the attempt-log-derived Progress stage matches.
    def apply_stage!(home:, learner:, item:, stage:, salt:)
      profile = STAGE_PROFILES.fetch(stage)
      last_reviewed = last_reviewed_for(profile)

      home.update!(
        suspended: false,
        state: profile[:state],
        box: profile[:level],
        interval_days: Srs::Scheduler.interval_for(profile[:level]),
        streak: profile[:streak],
        repetitions: profile[:repetitions],
        lapses: profile[:lapses],
        due_at: due_at_for(stage, salt),
        last_reviewed_at: last_reviewed,
        mastered_at: profile[:mastered] ? mastered_at_for(profile) : nil
      )

      append_anchor_attempt!(item: item, learner: learner, profile: profile,
                             reviewed_at: last_reviewed)
    end

    # The anchor attempt is what teaches the Progress dashboards the stage: a
    # CORRECT attempt whose interval_before == the gap survived. New == none.
    def append_anchor_attempt!(item:, learner:, profile:, reviewed_at:)
      survived = profile[:survived_days]
      return if survived.nil? # New: never correctly recalled

      item.attempts.create!(
        user_id: learner.id,
        grade: :good,
        correct: true,
        reviewed_at: reviewed_at || @now,
        interval_before: survived,
        interval_after: Srs::Scheduler.interval_for(profile[:level])
      )
    end

    # Vary the due dates so a believable chunk is due now/overdue and the rest is
    # spread into the future (drives Today + the 14-day forecast). New items are
    # always due now (nothing scheduled yet). Deterministic on `salt`.
    #
    # The due bucket is derived from `salt / STAGES.size` (NOT salt directly) so
    # it rotates INDEPENDENTLY of the stage — otherwise, since the stage is
    # `index % size`, the bucket would be locked in phase with the stage and the
    # "overdue" bucket (0) would never be reached. ~40% of non-new items end up
    # due now/overdue.
    def due_at_for(stage, salt)
      return @now if stage == :new # never scheduled yet -> show in Today now

      case (salt / STAGES.size) % 5
      when 0 then @now - 2.days  # overdue
      when 1 then @now           # due now
      when 2 then @now + 1.day   # tomorrow
      when 3 then @now + 3.days  # this week
      else        @now + 9.days  # next week-plus (lands in forecast tail)
      end
    end

    # Place the last review behind the survived gap so the timeline reads
    # plausibly (reviewed `survived_days` ago for spaced items).
    def last_reviewed_for(profile)
      survived = profile[:survived_days]
      return nil if survived.nil?

      @now - [ survived, 1 ].max.days
    end

    # Mastery was first earned around when the qualifying gap was survived.
    def mastered_at_for(profile)
      @now - profile[:survived_days].days
    end

    # --- Credentials + counts summary ------------------------------------
    def print_summary
      counts = current_counts
      puts ""
      puts "=" * 64
      puts "  demo:load complete — classroom demo seeded (scoped to #{DEMO_EMAIL_SUFFIX})"
      puts "=" * 64
      puts ""
      puts "  LOGIN CREDENTIALS (all passwords: #{DEMO_PASSWORD.inspect})"
      puts "  ----------------------------------------------------------------"
      puts "  Admin   : #{ADMIN[:email]}"
      puts "  Teacher : #{TEACHER[:email]}"
      STUDENTS.each_with_index do |s, i|
        label = [ "ahead", "middle", "behind" ][i]
        puts "  Student : #{s[:email].ljust(20)} (#{label})"
      end
      puts ""
      puts "  Cohort  : #{@cohort.name}  (join code: #{@cohort.join_code})"
      puts ""
      puts "  COUNTS"
      puts "  ----------------------------------------------------------------"
      puts "  admins ............ #{counts[:admins]}"
      puts "  teachers .......... #{counts[:teachers]}"
      puts "  students .......... #{counts[:students]}"
      puts "  subjects .......... #{counts[:subjects]}"
      puts "  lessons ........... #{counts[:lessons]}"
      puts "  items ............. #{counts[:items]}"
      puts "  enrollments ....... #{counts[:enrollments]}"
      puts "  assignments ....... #{counts[:assignments]}"
      puts "  review_states ..... #{counts[:review_states]}"
      puts "  attempts .......... #{counts[:attempts]}"
      puts "  teacher items due now ... #{counts[:owner_due]}"
      puts "  student states due now .. #{counts[:student_due]}"
      puts "=" * 64
      puts ""
    end

    def current_counts
      teacher_item_ids = teacher_items.pluck(:id)
      {
        admins: User.where(role: "admin", email_address: ADMIN[:email]).count,
        teachers: User.where(role: "teacher", email_address: TEACHER[:email]).count,
        students: User.where(role: "student").where("email_address LIKE ?", "%#{DEMO_EMAIL_SUFFIX}").count,
        subjects: @subjects.size,
        lessons: Lesson.where(subject_id: @subjects.map(&:id)).count,
        items: teacher_item_ids.size,
        enrollments: @cohort.enrollments.count,
        assignments: @cohort.assignments.count,
        review_states: ReviewState.where(user_id: @students.map(&:id)).count,
        attempts: Attempt.where(item_id: teacher_item_ids).count,
        owner_due: Item.where(id: teacher_item_ids).due(@now).count,
        student_due: ReviewState.where(user_id: @students.map(&:id)).due(@now).count
      }
    end

    # --- The believable study content (5 subjects x 5 lessons x 10 items) -
    # Real, themed prompt/answer material so the demo reads like genuine study
    # cards, not "Item 1". Five lessons per subject, ten items per lesson.
    CONTENT = [
      {
        name: "Spanish Vocabulary",
        description: "Core Spanish words and phrases for everyday conversation.",
        lessons: [
          {
            title: "Greetings & Courtesy",
            body: "Hellos, goodbyes, and polite words.",
            items: [
              [ "How do you say \"hello\" in Spanish?", "hola" ],
              [ "How do you say \"goodbye\" in Spanish?", "adiós" ],
              [ "How do you say \"please\" in Spanish?", "por favor" ],
              [ "How do you say \"thank you\" in Spanish?", "gracias" ],
              [ "How do you say \"you're welcome\" in Spanish?", "de nada" ],
              [ "How do you say \"good morning\" in Spanish?", "buenos días" ],
              [ "How do you say \"good night\" in Spanish?", "buenas noches" ],
              [ "How do you say \"excuse me\" in Spanish?", "perdón" ],
              [ "How do you say \"yes\" in Spanish?", "sí" ],
              [ "How do you say \"no\" in Spanish?", "no" ]
            ]
          },
          {
            title: "Numbers 1–10",
            body: "Counting from one to ten.",
            items: [
              [ "What is \"one\" in Spanish?", "uno" ],
              [ "What is \"two\" in Spanish?", "dos" ],
              [ "What is \"three\" in Spanish?", "tres" ],
              [ "What is \"four\" in Spanish?", "cuatro" ],
              [ "What is \"five\" in Spanish?", "cinco" ],
              [ "What is \"six\" in Spanish?", "seis" ],
              [ "What is \"seven\" in Spanish?", "siete" ],
              [ "What is \"eight\" in Spanish?", "ocho" ],
              [ "What is \"nine\" in Spanish?", "nueve" ],
              [ "What is \"ten\" in Spanish?", "diez" ]
            ]
          },
          {
            title: "Colors",
            body: "The most common colors.",
            items: [
              [ "What is \"red\" in Spanish?", "rojo" ],
              [ "What is \"blue\" in Spanish?", "azul" ],
              [ "What is \"green\" in Spanish?", "verde" ],
              [ "What is \"yellow\" in Spanish?", "amarillo" ],
              [ "What is \"black\" in Spanish?", "negro" ],
              [ "What is \"white\" in Spanish?", "blanco" ],
              [ "What is \"orange\" (color) in Spanish?", "naranja" ],
              [ "What is \"purple\" in Spanish?", "morado" ],
              [ "What is \"brown\" in Spanish?", "marrón" ],
              [ "What is \"pink\" in Spanish?", "rosa" ]
            ]
          },
          {
            title: "Days of the Week",
            body: "Monday through Sunday.",
            items: [
              [ "What is \"Monday\" in Spanish?", "lunes" ],
              [ "What is \"Tuesday\" in Spanish?", "martes" ],
              [ "What is \"Wednesday\" in Spanish?", "miércoles" ],
              [ "What is \"Thursday\" in Spanish?", "jueves" ],
              [ "What is \"Friday\" in Spanish?", "viernes" ],
              [ "What is \"Saturday\" in Spanish?", "sábado" ],
              [ "What is \"Sunday\" in Spanish?", "domingo" ],
              [ "What is \"today\" in Spanish?", "hoy" ],
              [ "What is \"tomorrow\" in Spanish?", "mañana" ],
              [ "What is \"week\" in Spanish?", "semana" ]
            ]
          },
          {
            title: "Common Verbs",
            body: "Everyday action words (infinitives).",
            items: [
              [ "What is \"to be\" (permanent) in Spanish?", "ser" ],
              [ "What is \"to have\" in Spanish?", "tener" ],
              [ "What is \"to go\" in Spanish?", "ir" ],
              [ "What is \"to eat\" in Spanish?", "comer" ],
              [ "What is \"to drink\" in Spanish?", "beber" ],
              [ "What is \"to speak\" in Spanish?", "hablar" ],
              [ "What is \"to live\" in Spanish?", "vivir" ],
              [ "What is \"to want\" in Spanish?", "querer" ],
              [ "What is \"to make/do\" in Spanish?", "hacer" ],
              [ "What is \"to see\" in Spanish?", "ver" ]
            ]
          }
        ]
      },
      {
        name: "Biology",
        description: "Foundational cell biology, genetics, and the human body.",
        lessons: [
          {
            title: "The Cell",
            body: "Cell structures and their jobs.",
            items: [
              [ "What is the \"control center\" of the cell?", "the nucleus" ],
              [ "Which organelle is the powerhouse of the cell?", "the mitochondrion" ],
              [ "Where does photosynthesis occur in plant cells?", "the chloroplast" ],
              [ "What surrounds and protects the cell?", "the cell membrane" ],
              [ "What jelly-like fluid fills the cell?", "the cytoplasm" ],
              [ "Which organelle makes proteins?", "the ribosome" ],
              [ "What stores water and waste in plant cells?", "the vacuole" ],
              [ "What rigid layer surrounds a plant cell?", "the cell wall" ],
              [ "Which organelle packages and ships proteins?", "the Golgi apparatus" ],
              [ "What is the basic unit of life?", "the cell" ]
            ]
          },
          {
            title: "Genetics Basics",
            body: "DNA, genes, and inheritance.",
            items: [
              [ "What molecule carries genetic information?", "DNA" ],
              [ "What is a segment of DNA coding for a trait called?", "a gene" ],
              [ "How many chromosomes do humans normally have?", "46" ],
              [ "What are the four DNA bases?", "adenine, thymine, guanine, cytosine" ],
              [ "Which base pairs with adenine in DNA?", "thymine" ],
              [ "Which base pairs with guanine?", "cytosine" ],
              [ "What is an organism's genetic makeup called?", "its genotype" ],
              [ "What is an organism's observable traits called?", "its phenotype" ],
              [ "What do we call a stronger, masking allele?", "dominant" ],
              [ "Who is known as the father of genetics?", "Gregor Mendel" ]
            ]
          },
          {
            title: "Human Body Systems",
            body: "Major systems and what they do.",
            items: [
              [ "Which system pumps blood around the body?", "the circulatory system" ],
              [ "Which system takes in oxygen?", "the respiratory system" ],
              [ "Which system breaks down food?", "the digestive system" ],
              [ "Which system supports and shapes the body?", "the skeletal system" ],
              [ "Which system enables movement?", "the muscular system" ],
              [ "Which system sends electrical signals?", "the nervous system" ],
              [ "Which organ pumps blood?", "the heart" ],
              [ "Which organ filters blood to make urine?", "the kidney" ],
              [ "Which organ exchanges oxygen and carbon dioxide?", "the lungs" ],
              [ "Which organ controls the body and thought?", "the brain" ]
            ]
          },
          {
            title: "Ecology",
            body: "Living things and their environment.",
            items: [
              [ "What do we call an organism that makes its own food?", "a producer" ],
              [ "What do we call an organism that eats others?", "a consumer" ],
              [ "What breaks down dead matter?", "a decomposer" ],
              [ "What is a community plus its environment called?", "an ecosystem" ],
              [ "What is the role an organism plays called?", "its niche" ],
              [ "What is a meat-eating animal called?", "a carnivore" ],
              [ "What is a plant-eating animal called?", "a herbivore" ],
              [ "What gas do plants release in photosynthesis?", "oxygen" ],
              [ "What gas do plants take in for photosynthesis?", "carbon dioxide" ],
              [ "What is the variety of life in an area called?", "biodiversity" ]
            ]
          },
          {
            title: "Classification",
            body: "How living things are grouped.",
            items: [
              [ "What is the broadest taxonomic rank?", "domain" ],
              [ "What two-word naming system names species?", "binomial nomenclature" ],
              [ "What kingdom do mushrooms belong to?", "Fungi" ],
              [ "What kingdom do humans belong to?", "Animalia" ],
              [ "What kingdom do trees belong to?", "Plantae" ],
              [ "Animals with backbones are called?", "vertebrates" ],
              [ "Animals without backbones are called?", "invertebrates" ],
              [ "Warm-blooded, hair-bearing animals are?", "mammals" ],
              [ "Who devised the modern classification system?", "Carl Linnaeus" ],
              [ "The rank just below family is the?", "genus" ]
            ]
          }
        ]
      },
      {
        name: "World History",
        description: "Key events, people, and turning points across world history.",
        lessons: [
          {
            title: "Ancient Civilizations",
            body: "The earliest great societies.",
            items: [
              [ "Along which river did ancient Egypt arise?", "the Nile" ],
              [ "What is the region 'between the rivers' called?", "Mesopotamia" ],
              [ "What writing system did the Sumerians use?", "cuneiform" ],
              [ "Which civilization built the Great Pyramids?", "ancient Egypt" ],
              [ "What was an Egyptian king called?", "a pharaoh" ],
              [ "Which code is one of the earliest written laws?", "the Code of Hammurabi" ],
              [ "Which civilization invented democracy?", "ancient Greece" ],
              [ "Which empire built roads across Europe?", "the Roman Empire" ],
              [ "What wall did ancient China build for defense?", "the Great Wall" ],
              [ "Which river was central to the Indus civilization?", "the Indus" ]
            ]
          },
          {
            title: "The Middle Ages",
            body: "Europe from roughly 500 to 1500.",
            items: [
              [ "What economic system organized medieval society?", "feudalism" ],
              [ "Who held land in exchange for military service?", "a vassal (knight)" ],
              [ "What were the religious wars to the Holy Land called?", "the Crusades" ],
              [ "What plague devastated 14th-century Europe?", "the Black Death" ],
              [ "What document limited the English king's power in 1215?", "the Magna Carta" ],
              [ "What were fortified noble homes called?", "castles" ],
              [ "Who copied books in medieval monasteries?", "monks" ],
              [ "What empire fell in 1453 to the Ottomans?", "the Byzantine Empire" ],
              [ "What trade routes linked Europe and Asia?", "the Silk Road" ],
              [ "Who led the Franks and was crowned emperor in 800?", "Charlemagne" ]
            ]
          },
          {
            title: "Renaissance & Exploration",
            body: "Rebirth of learning and the age of discovery.",
            items: [
              [ "In which country did the Renaissance begin?", "Italy" ],
              [ "Who painted the Mona Lisa?", "Leonardo da Vinci" ],
              [ "Who sculpted David and painted the Sistine Chapel?", "Michelangelo" ],
              [ "Who sailed west and reached the Americas in 1492?", "Christopher Columbus" ],
              [ "Whose crew first circumnavigated the globe?", "Ferdinand Magellan" ],
              [ "What invention spread ideas rapidly in the 1400s?", "the printing press" ],
              [ "Who invented the printing press in Europe?", "Johannes Gutenberg" ],
              [ "What sea route did Vasco da Gama open to India?", "around Africa" ],
              [ "What movement reformed the Western Church in 1517?", "the Reformation" ],
              [ "Who started the Reformation with 95 theses?", "Martin Luther" ]
            ]
          },
          {
            title: "Revolutions",
            body: "Upheavals that reshaped the modern world.",
            items: [
              [ "In what year did the American colonies declare independence?", "1776" ],
              [ "What 1789 revolution overthrew the French monarchy?", "the French Revolution" ],
              [ "What shift to machine production began around 1760?", "the Industrial Revolution" ],
              [ "Who wrote the Declaration of Independence?", "Thomas Jefferson" ],
              [ "What Paris prison was stormed in 1789?", "the Bastille" ],
              [ "Who became emperor of France in 1804?", "Napoleon Bonaparte" ],
              [ "What machine powered early factories?", "the steam engine" ],
              [ "Who improved the steam engine in the 1700s?", "James Watt" ],
              [ "What 1917 revolution created the Soviet Union?", "the Russian Revolution" ],
              [ "Who led the Bolsheviks in 1917?", "Vladimir Lenin" ]
            ]
          },
          {
            title: "The 20th Century",
            body: "World wars and the decades after.",
            items: [
              [ "In what year did World War I begin?", "1914" ],
              [ "In what year did World War II end?", "1945" ],
              [ "What event triggered the Great Depression?", "the 1929 stock market crash" ],
              [ "What wall divided Berlin from 1961 to 1989?", "the Berlin Wall" ],
              [ "What tense rivalry followed WWII between the US and USSR?", "the Cold War" ],
              [ "Who was the first human in space?", "Yuri Gagarin" ],
              [ "Who first walked on the Moon, in 1969?", "Neil Armstrong" ],
              [ "Who led nonviolent resistance in India?", "Mahatma Gandhi" ],
              [ "Who led the US civil rights movement of the 1960s?", "Martin Luther King Jr." ],
              [ "What global body formed in 1945 to keep peace?", "the United Nations" ]
            ]
          }
        ]
      },
      {
        name: "Geography",
        description: "Countries, capitals, and physical features of the world.",
        lessons: [
          {
            title: "European Capitals",
            body: "Match each country to its capital.",
            items: [
              [ "Capital of France?", "Paris" ],
              [ "Capital of Germany?", "Berlin" ],
              [ "Capital of Spain?", "Madrid" ],
              [ "Capital of Italy?", "Rome" ],
              [ "Capital of Portugal?", "Lisbon" ],
              [ "Capital of Greece?", "Athens" ],
              [ "Capital of the Netherlands?", "Amsterdam" ],
              [ "Capital of Poland?", "Warsaw" ],
              [ "Capital of Sweden?", "Stockholm" ],
              [ "Capital of Ireland?", "Dublin" ]
            ]
          },
          {
            title: "World Capitals",
            body: "Capitals beyond Europe.",
            items: [
              [ "Capital of Japan?", "Tokyo" ],
              [ "Capital of Canada?", "Ottawa" ],
              [ "Capital of Australia?", "Canberra" ],
              [ "Capital of Brazil?", "Brasília" ],
              [ "Capital of Egypt?", "Cairo" ],
              [ "Capital of India?", "New Delhi" ],
              [ "Capital of China?", "Beijing" ],
              [ "Capital of Mexico?", "Mexico City" ],
              [ "Capital of South Africa (legislative)?", "Cape Town" ],
              [ "Capital of Argentina?", "Buenos Aires" ]
            ]
          },
          {
            title: "Rivers & Mountains",
            body: "Major physical features.",
            items: [
              [ "What is the longest river in the world?", "the Nile" ],
              [ "What is the highest mountain on Earth?", "Mount Everest" ],
              [ "On which continent is the Amazon River?", "South America" ],
              [ "Which mountain range separates Europe and Asia?", "the Urals" ],
              [ "Which mountain range runs along western South America?", "the Andes" ],
              [ "What is the largest desert (hot) on Earth?", "the Sahara" ],
              [ "Which river runs through London?", "the Thames" ],
              [ "Which river runs through Egypt?", "the Nile" ],
              [ "What is the tallest waterfall in the world?", "Angel Falls" ],
              [ "Which European range includes Mont Blanc?", "the Alps" ]
            ]
          },
          {
            title: "Oceans & Seas",
            body: "The world's great bodies of water.",
            items: [
              [ "What is the largest ocean?", "the Pacific Ocean" ],
              [ "What is the second-largest ocean?", "the Atlantic Ocean" ],
              [ "What is the smallest ocean?", "the Arctic Ocean" ],
              [ "Which ocean borders eastern Africa and India?", "the Indian Ocean" ],
              [ "What sea lies between Europe and Africa?", "the Mediterranean Sea" ],
              [ "What is the saltiest large body, between Israel and Jordan?", "the Dead Sea" ],
              [ "What sea separates Saudi Arabia from Africa?", "the Red Sea" ],
              [ "What large lake is the world's biggest by area?", "the Caspian Sea" ],
              [ "What ocean lies south, around Antarctica?", "the Southern Ocean" ],
              [ "What sea is north of Turkey?", "the Black Sea" ]
            ]
          },
          {
            title: "Continents",
            body: "The seven continents and their facts.",
            items: [
              [ "How many continents are there?", "seven" ],
              [ "What is the largest continent by area?", "Asia" ],
              [ "What is the smallest continent?", "Australia" ],
              [ "Which continent is the coldest?", "Antarctica" ],
              [ "On which continent is the Sahara?", "Africa" ],
              [ "On which continent is the Amazon rainforest?", "South America" ],
              [ "Which continent has the most countries?", "Africa" ],
              [ "Which continent is both north and a continent name?", "North America" ],
              [ "Which continent has no permanent residents?", "Antarctica" ],
              [ "On which continent is the country of France?", "Europe" ]
            ]
          }
        ]
      },
      {
        name: "Music Theory",
        description: "Notes, rhythm, scales, and the language of music.",
        lessons: [
          {
            title: "Notes & the Staff",
            body: "Reading pitches on the staff.",
            items: [
              [ "How many lines does a musical staff have?", "five" ],
              [ "What clef is used for high notes?", "the treble clef" ],
              [ "What clef is used for low notes?", "the bass clef" ],
              [ "What are the treble-clef line notes (bottom to top)?", "E, G, B, D, F" ],
              [ "What are the treble-clef space notes (bottom to top)?", "F, A, C, E" ],
              [ "How many natural notes are there before repeating?", "seven (A–G)" ],
              [ "What symbol raises a note by a half step?", "a sharp" ],
              [ "What symbol lowers a note by a half step?", "a flat" ],
              [ "What symbol cancels a sharp or flat?", "a natural" ],
              [ "What is the distance from one note to the same note higher?", "an octave" ]
            ]
          },
          {
            title: "Rhythm & Note Values",
            body: "How long notes last.",
            items: [
              [ "How many beats is a whole note (in 4/4)?", "four" ],
              [ "How many beats is a half note (in 4/4)?", "two" ],
              [ "How many beats is a quarter note (in 4/4)?", "one" ],
              [ "How many eighth notes fit in one beat (in 4/4)?", "two" ],
              [ "What does a dot after a note do?", "adds half its value" ],
              [ "What symbol marks silence?", "a rest" ],
              [ "What do the two numbers at the start of music show?", "the time signature" ],
              [ "How many beats per measure in 4/4 time?", "four" ],
              [ "What note gets the beat in 4/4 time?", "the quarter note" ],
              [ "What is the speed of the music called?", "the tempo" ]
            ]
          },
          {
            title: "Scales & Keys",
            body: "Building blocks of melody.",
            items: [
              [ "How many notes are in a major scale (one octave)?", "eight" ],
              [ "What is the pattern of a major scale (W/H)?", "W-W-H-W-W-W-H" ],
              [ "What scale has no sharps or flats?", "C major" ],
              [ "What is the first note of a scale called?", "the tonic" ],
              [ "What is the fifth note of a scale called?", "the dominant" ],
              [ "What tells you the key at the start of a piece?", "the key signature" ],
              [ "What is the relative minor of C major?", "A minor" ],
              [ "How many half steps in an octave?", "twelve" ],
              [ "What is a five-note scale called?", "a pentatonic scale" ],
              [ "What scale uses all twelve half steps?", "the chromatic scale" ]
            ]
          },
          {
            title: "Chords & Harmony",
            body: "Stacking notes together.",
            items: [
              [ "How many notes make a basic triad?", "three" ],
              [ "What three scale degrees form a major triad?", "1, 3, 5" ],
              [ "What chord is built on the tonic (degree 1)?", "the tonic chord" ],
              [ "What chord is built on the fifth degree?", "the dominant chord" ],
              [ "What do we call two or more notes sounding together?", "a chord (harmony)" ],
              [ "What is the distance between two pitches called?", "an interval" ],
              [ "What interval spans five scale steps?", "a fifth" ],
              [ "What quality of triad sounds 'sad'?", "minor" ],
              [ "What quality of triad sounds 'happy'?", "major" ],
              [ "What is a broken chord played one note at a time?", "an arpeggio" ]
            ]
          },
          {
            title: "Dynamics & Terms",
            body: "Italian terms for expression.",
            items: [
              [ "What does 'forte' mean?", "loud" ],
              [ "What does 'piano' (dynamic) mean?", "soft" ],
              [ "What does 'crescendo' mean?", "gradually louder" ],
              [ "What does 'decrescendo' (diminuendo) mean?", "gradually softer" ],
              [ "What does 'allegro' mean?", "fast (lively)" ],
              [ "What does 'adagio' mean?", "slow" ],
              [ "What does 'legato' mean?", "smooth and connected" ],
              [ "What does 'staccato' mean?", "short and detached" ],
              [ "What does 'fermata' indicate?", "hold the note longer" ],
              [ "What does 'da capo' (D.C.) mean?", "from the beginning" ]
            ]
          }
        ]
      }
    ].freeze
  end
end
