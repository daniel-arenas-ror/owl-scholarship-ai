module AdminHelper
  def admin_nav_link(label, path)
    active = current_page?(path) || (path != admin_root_path && request.path.start_with?(path))
    classes = [ "rounded px-2 py-1.5 text-sm" ]
    classes << (active ? "bg-owl-500 font-medium text-white" : "text-muted hover:bg-owl-50")
    link_to label, path, class: classes.join(" ")
  end

  def rating_badge(rating)
    return tag.span("—", class: "text-muted") if rating.blank?

    up = rating.to_s == "up"
    tag.span(up ? "👍" : "👎",
      class: "rounded px-1.5 py-0.5 text-xs #{up ? 'bg-emerald-100' : 'bg-red-100'}")
  end

  def agent_badge(agent)
    return "" if agent.blank?

    label = agent == "scholarship_expert" ? "🎓 experto" : "asesor"
    tag.span(label, class: "rounded bg-owl-50 px-1.5 py-0.5 text-xs text-owl-700")
  end

  def sync_badge(record)
    if record.last_push_status == "error"
      tag.span("error", class: "rounded bg-red-100 px-1.5 py-0.5 text-xs text-red-800")
    elsif record.pending_push?
      tag.span("cambios sin enviar", class: "rounded bg-amber-100 px-1.5 py-0.5 text-xs text-amber-800")
    else
      tag.span("sincronizada", class: "rounded bg-emerald-100 px-1.5 py-0.5 text-xs text-emerald-800")
    end
  end
end
