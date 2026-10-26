import { ArrowUpRight, CheckSquare, Clock } from "@phosphor-icons/react";
import { Link } from "react-router-dom";
import { cx, formatDuration, formatRelative, formatTime } from "../lib/format";
import type { RecordingSummary } from "../types";
import { Avatar, PlayButton, StatusPill } from "./ui";

export function RecordingRow({
  recording,
  showDay = false,
}: {
  recording: RecordingSummary;
  showDay?: boolean;
}) {
  const pending = recording.status !== "ready";
  return (
    <article className={cx("rec-row", pending && "rec-row--pending")}>
      <div className="rec-row__time">
        <span className="mono">{showDay ? formatRelative(recording.recorded_at) : formatTime(recording.recorded_at)}</span>
      </div>
      <div className="rec-row__avatar">
        <Avatar contact={recording.contact} name={recording.contact?.name || "我"} size="sm" />
      </div>
      <div className="rec-row__body">
        <div className="rec-row__titleline">
          <Link to={`/recordings/${recording.id}`} className="rec-row__title">
            {recording.title}
          </Link>
          {recording.category && recording.category !== "语音备忘" ? (
            <span className="rec-row__kind">{recording.category}</span>
          ) : null}
          {recording.kind === "voice" ? <span className="rec-row__kind">语音备忘</span> : null}
          {recording.is_demo ? <span className="rec-row__kind">演示</span> : null}
        </div>
        <p className="rec-row__excerpt">
          {recording.status === "failed"
            ? recording.error || "处理失败，可以重新试一次。"
            : recording.excerpt || (recording.status === "ready" ? "这段录音还没有摘要。" : "正在整理这段录音。")}
        </p>
        <div className="rec-row__meta">
          {recording.contact ? (
            <span>{recording.contact.name}</span>
          ) : recording.kind === "voice" ? (
            <span>单人录音</span>
          ) : (
            <span>未识别联系人</span>
          )}
          <span className="rec-row__meta-duration mono">{formatDuration(recording.duration)}</span>
          {recording.action_open > 0 ? (
            <span className="rec-row__actions">
              <CheckSquare size={13} aria-hidden="true" />
              {recording.action_open} 件待办
            </span>
          ) : null}
          {recording.status === "failed" ? <span className="rec-row__error">需要重试</span> : null}
        </div>
      </div>
      <div className="rec-row__status">
        <StatusPill
          status={recording.status}
          label={recording.status_label}
          stageLabel={recording.stage_label}
          error={recording.error}
        />
      </div>
      <div className="rec-row__duration mono">
        <Clock size={13} aria-hidden="true" />
        {formatDuration(recording.duration)}
      </div>
      <div className="rec-row__play">
        <PlayButton recording={recording} size="sm" />
        <Link
          to={`/recordings/${recording.id}`}
          className="rec-row__open"
          aria-label={`打开 ${recording.title}`}
        >
          <ArrowUpRight size={15} />
        </Link>
      </div>
    </article>
  );
}

export function RecordingRows({
  items,
  showDay = false,
}: {
  items: RecordingSummary[];
  showDay?: boolean;
}) {
  return (
    <div className="rec-list">
      {items.map((recording) => (
        <RecordingRow key={recording.id} recording={recording} showDay={showDay} />
      ))}
    </div>
  );
}
