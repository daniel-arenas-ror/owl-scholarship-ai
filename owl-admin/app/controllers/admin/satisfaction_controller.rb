class Admin::SatisfactionController < Admin::BaseController
  def show
    @overall = rating_totals(Feedback.group(:rating).count)

    @by_agent = grouped_series(
      Feedback.joins(:message).where.not(messages: { agent: nil })
        .group("messages.agent").group(:rating).count
    )

    @by_scholarship = grouped_series(
      Feedback.joins(:message)
        .joins("CROSS JOIN LATERAL jsonb_array_elements(messages.citations) AS cite")
        .group(Arel.sql("cite ->> 'title'")).group(:rating).count
    )

    @over_time = grouped_series(
      Feedback.group(Arel.sql("DATE(feedbacks.created_at)")).group(:rating).count,
      sort_keys: true
    )
  end

  private

  def normalize_rating(key)
    return "up" if [ "up", 1, "1" ].include?(key)
    return "down" if [ "down", 0, "0" ].include?(key)

    nil
  end

  def rating_totals(counts)
    up = counts.sum { |key, n| normalize_rating(key) == "up" ? n : 0 }
    down = counts.sum { |key, n| normalize_rating(key) == "down" ? n : 0 }
    { "👍" => up, "👎" => down }
  end

  # counts: { [group, rating] => n } -> [{ name: "👍", data: {group => n} }, { name: "👎", ... }]
  def grouped_series(counts, sort_keys: false)
    up = Hash.new(0)
    down = Hash.new(0)
    counts.each do |(group, rating), n|
      bucket = { "up" => up, "down" => down }[normalize_rating(rating)]
      next unless bucket

      bucket[group.presence.to_s.presence || "—"] += n
    end
    up = up.sort.to_h if sort_keys
    down = down.sort.to_h if sort_keys
    [ { name: "👍", data: up }, { name: "👎", data: down } ]
  end
end
