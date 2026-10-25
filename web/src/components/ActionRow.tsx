import { useState } from "react";
import { ArrowUpRight, CalendarBlank, Check } from "@phosphor-icons/react";
import { Link } from "react-router-dom";
import { api } from "../lib/api";
import { cx, dueStatus, formatDuration } from "../lib/format";
import { useToast } from "../contexts";
import type { ActionItem } from "../types";

export function ActionRow({
  action,
  onChanged,
  showQuote = false,
  compact = false,
}: {
  action: ActionItem;
  onChanged: (action: ActionItem, done: boolean) => void;
  showQuote?: boolean;
  compact?: boolean;
}) {
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  const due = dueStatus(action.due_date, action.done);

  const toggle = async () => {
    if (busy) return;
    const next = !action.done;
    setBusy(true);
    onChanged({ ...action, done: next }, next);
    try {
      await api.patch(`/api/actions/${action.id}`, { done: next });
      window.dispatchEvent(new Event("shengce:refresh"));
    } catch (error) {
      onChanged(action, action.done);
      toast.show(error instanceof Error ? error.message : "更新待办失败。", "error");
    } finally {
      setBusy(false);
    }
  };

  const recording = action.recording;
  const timecode = action.segment_start;
  const link = recording
    ? `/recordings/${recording.id}${timecode !== null ? `?t=${Math.floor(timecode)}` : ""}`
    : null;

  return (
    <div className={cx("action-row", action.done && "is-done", compact && "action-row--compact")}>
      <label className="action-check">
        <input type="checkbox" checked={action.done} onChange={() => void toggle()} disabled={busy} />
        <span className="action-check__box" aria-hidden="true">
          {action.done ? <Check size={13} weight="bold" /> : null}
        </span>
        <span className="visually-hidden">{action.done ? "标记为未完成" : "标记为完成"}</span>
      </label>
      <div className="action-row__body">
        <p className="action-row__text">{action.text}</p>
        {showQuote && action.detail ? <p className="action-row__quote">“{action.detail}”</p> : null}
        <div className="action-row__meta">
          {!action.done ? (
            <span className={cx("action-row__due", `action-row__due--${due.tone}`)}>
              <CalendarBlank size={13} aria-hidden="true" />
              {due.tone === "overdue" ? "已逾期 " : ""}
              {action.due_label || due.label}
            </span>
          ) : null}
          {recording && link ? (
            <Link to={link} className="action-row__source">
              <span className="action-row__source-title">
                {recording.contact?.name || recording.title}
              </span>
              {timecode !== null ? <span className="mono">{formatDuration(timecode)}</span> : null}
              <ArrowUpRight size={13} aria-hidden="true" />
            </Link>
          ) : null}
        </div>
      </div>
    </div>
  );
}
