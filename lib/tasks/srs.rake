# frozen_string_literal: true

namespace :srs do
  desc "Rebuild SRS state (owner inline + assigned review_states) from the attempt log (plan §6)"
  task rebuild: :environment do
    count = Srs::Rebuild.call
    puts "srs:rebuild — replayed attempts into #{count} state home(s) (owner + assigned)."
  end
end
