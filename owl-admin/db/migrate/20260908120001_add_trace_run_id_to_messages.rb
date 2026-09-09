class AddTraceRunIdToMessages < ActiveRecord::Migration[8.1]
  def change
    # The LangSmith root-run id owl-api generates per turn, so the admin
    # transcript can link straight to the trace.
    add_column :messages, :trace_run_id, :string
  end
end
