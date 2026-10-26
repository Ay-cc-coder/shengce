import { useEffect, useMemo, useRef } from "react";
import { ChatCircleDots } from "@phosphor-icons/react";
import { cx, formatDuration } from "../lib/format";
import type { RecordingDetail } from "../types";
import { Avatar, EmptyState } from "./ui";

function isMine(speaker: string): boolean {
  return speaker === "me" || speaker === "2";
}

export function ChatTranscript({
  recording,
  currentTime,
  focusIdx,
  onSeek,
  onAddAction,
}: {
  recording: RecordingDetail;
  currentTime: number;
  focusIdx?: number | null;
  onSeek: (time: number) => void;
  onAddAction?: (segment: RecordingDetail["segments"][number]) => void;
}) {
  const refs = useRef<Record<number, HTMLDivElement | null>>({});
  const activeIdx = useMemo(() => {
    let index: number | null = null;
    for (const segment of recording.segments) {
      if (currentTime + 0.05 >= segment.start && currentTime < segment.end + 0.25) {
        index = segment.idx;
      }
    }
    return index;
  }, [recording.segments, currentTime]);

  useEffect(() => {
    if (focusIdx === null || focusIdx === undefined) return;
    const node = refs.current[focusIdx];
    if (!node) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    node.scrollIntoView({ block: "center", behavior: reduce ? "auto" : "smooth" });
  }, [focusIdx]);

  if (!recording.segments.length) {
    return (
      <EmptyState
        compact
        icon={<ChatCircleDots size={24} />}
        title="还没有对话"
        action={
          recording.status === "failed" ? (
            <span className="muted">重新处理后再看这里。</span>
          ) : (
            <span className="muted">转写完成后，这里会按时间排成对话。</span>
          )
        }
      />
    );
  }

  return (
    <div className="chat" aria-label="录音对话">
      {recording.segments.map((segment) => {
        const mine = isMine(segment.speaker);
        const highlighted = focusIdx === segment.idx;
        const active = activeIdx === segment.idx;
        return (
          <div
            key={segment.id}
            ref={(node) => {
              refs.current[segment.idx] = node;
            }}
            className={cx(
              "chat-turn",
              mine ? "chat-turn--mine" : "chat-turn--theirs",
              active && "is-active",
              highlighted && "is-focus"
            )}
          >
            <Avatar
              contact={mine ? null : recording.contact}
              name={recording.speakers[segment.speaker] || segment.speaker_name}
              size="sm"
            />
            <div className="chat-turn__body">
              <div className="chat-turn__meta">
                <span className="chat-turn__speaker">
                  {recording.speakers[segment.speaker] || segment.speaker_name}
                </span>
                <button
                  type="button"
                  className="chat-turn__time mono"
                  onClick={() => onSeek(segment.start)}
                  aria-label={`从 ${formatDuration(segment.start)} 开始播放`}
                >
                  {formatDuration(segment.start)}
                </button>
              </div>
              <p className="chat-turn__bubble">{segment.text}</p>
              {onAddAction ? (
                <button
                  type="button"
                  className="chat-turn__todo"
                  onClick={() => onAddAction(segment)}
                >
                  + 待办
                </button>
              ) : null}
            </div>
          </div>
        );
      })}
    </div>
  );
}
