namespace :fine_tuning do
  desc "Export the SFT corpus (OpenAI chat JSONL) from 👍 + annotated turns"
  task :export, [ :out_dir ] => :environment do |_task, args|
    result = FineTuning::Exporter.new(out_dir: args[:out_dir]).run
    puts result.summary
  end
end
