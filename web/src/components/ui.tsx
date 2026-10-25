import { useRef, useState, type ReactNode } from "react";
import {
  CircleNotch,
  MagnifyingGlass,
  Pause,
  Play,
  UploadSimple,
  X,
} from "@phosphor-icons/react";
import { Link } from "react-router-dom";
import { api } from "../lib/api";
import { cx, initials } from "../lib/format";
import { usePlayer, useToast } from "../contexts";
import type { Contact, RecordingSummary, Status } from "../types";

export function Avatar({
  contact,
  name,
  size = "md",
}: {
  contact?: Contact | null;
  name?: string;
  size?: "sm" | "md" | "lg" | "xl";
}) {
  const label = contact?.name || name || "";
  const color = contact?.color || "sand";
  return (
    <span
      className={cx("avatar", `avatar--${size}`, `avatar--${color}`)}
      aria-hidden="true"
      title={label || undefined}
    >
      {initials(contact?.initials || label)}
    </span>
  );
}

export function PageHead({
  title,
  description,
  actions,
  className,
}: {
  title: string;
  description?: ReactNode;
  actions?: ReactNode;
  className?: string;
}) {
  return (
    <header className={cx("page-head", className)}>
      <div className="page-head__text">
        <h1>{title}</h1>
        {description ? <p className="page-head__lede">{description}</p> : null}
      </div>
      {actions ? <div className="page-head__actions">{actions}</div> : null}
    </header>
  );
}

export function StatusPill({
  status,
  label,
  stageLabel,
  error,
  showReady = false,
  className,
}: {
  status: Status;
  label: string;
  stageLabel?: string;
  error?: string | null;
  showReady?: boolean;
  className?: string;
}) {
  if (status === "ready" && !showReady) return null;
  const text = status === "processing" || status === "queued" ? stageLabel || label : label;
  return (
    <span
      className={cx("status-pill", `status-pill--${status}`, className)}
      title={error || text}
    >
      <span className="status-pill__dot" aria-hidden="true" />
      {text}
    </span>
  );
}

export function PlayButton({
  recording,
  size = "md",
  startAt,
  className,
}: {
  recording: RecordingSummary;
  size?: "sm" | "md" | "lg" | "xl";
  startAt?: number;
  className?: string;
}) {
  const player = usePlayer();
  const canPlay = recording.has_audio;
  const active = player.isCurrent(recording.id);
  const playing = active && player.playing;
  const iconSize = size === "xl" ? 26 : size === "lg" ? 22 : size === "md" ? 17 : 14;

  const toggle = () => {
    if (!canPlay) return;
    player.toggle(
      {
        id: recording.id,
        title: recording.title,
        kind: recording.kind,
        src: recording.audio_url || `/api/recordings/${recording.id}/audio`,
        duration: recording.duration,
        contact: recording.contact,
        waveform: recording.waveform || [],
      },
      startAt
    );
  };

  return (
    <button
      type="button"
      className={cx("play-button", `play-button--${size}`, playing && "is-playing", className)}
      onClick={toggle}
      disabled={!canPlay}
      aria-label={
        !canPlay
          ? "音频尚未就绪"
          : playing
            ? `暂停 ${recording.title}`
            : `播放 ${recording.title}`
      }
      title={!canPlay ? (recording.error || "音频处理中") : undefined}
    >
      {playing ? <Pause size={iconSize} weight="fill" /> : <Play size={iconSize} weight="fill" />}
    </button>
  );
}

export function UploadButton({
  onDone,
  className,
  label = "上传文件",
}: {
  onDone?: (item: RecordingSummary) => void;
  className?: string;
  label?: string;
}) {
  const inputRef = useRef<HTMLInputElement | null>(null);
  const [uploading, setUploading] = useState(false);
  const toast = useToast();

  const handleFile = async (file: File | undefined) => {
    if (!file) return;
    setUploading(true);
    try {
      const result = await api.upload<{ item: RecordingSummary }>(file);
      toast.show(`已上传 ${file.name}，正在排队整理。`, "success");
      window.dispatchEvent(new Event("shengce:refresh"));
      if (result.item) onDone?.(result.item);
    } catch (error) {
      toast.show(error instanceof Error ? error.message : "上传失败。", "error");
    } finally {
      setUploading(false);
      if (inputRef.current) inputRef.current.value = "";
    }
  };

  return (
    <>
      <input
        ref={inputRef}
        type="file"
        className="visually-hidden"
        onChange={(event) => void handleFile(event.target.files?.[0])}
        tabIndex={-1}
        aria-hidden="true"
      />
      <button
        type="button"
        className={cx("btn btn--secondary", className)}
        onClick={() => inputRef.current?.click()}
        disabled={uploading}
      >
        {uploading ? (
          <CircleNotch size={16} className="spin" aria-hidden="true" />
        ) : (
          <UploadSimple size={16} aria-hidden="true" />
        )}
        {uploading ? "上传中" : label}
      </button>
    </>
  );
}

export function EmptyState({
  icon,
  title,
  children,
  action,
  compact = false,
}: {
  icon?: ReactNode;
  title: string;
  children?: ReactNode;
  action?: ReactNode;
  compact?: boolean;
}) {
  return (
    <div className={cx("empty-state", compact && "empty-state--compact")}>
      {icon ? <div className="empty-state__icon">{icon}</div> : null}
      <h2>{title}</h2>
      {children ? <div className="empty-state__body">{children}</div> : null}
      {action ? <div className="empty-state__action">{action}</div> : null}
    </div>
  );
}

export function SearchField({
  value,
  onChange,
  placeholder = "搜索",
  label,
  className,
}: {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  label?: string;
  className?: string;
}) {
  return (
    <label className={cx("search-field", className)}>
      <MagnifyingGlass size={16} aria-hidden="true" />
      <span className="visually-hidden">{label || placeholder}</span>
      <input
        type="search"
        value={value}
        placeholder={placeholder}
        onChange={(event) => onChange(event.target.value)}
        spellCheck={false}
      />
      {value ? (
        <button
          type="button"
          className="search-field__clear"
          onClick={() => onChange("")}
          aria-label="清空搜索"
        >
          <X size={14} />
        </button>
      ) : null}
    </label>
  );
}

export function Tag({ children, tone }: { children: ReactNode; tone?: "amber" | "muted" }) {
  return <span className={cx("tag", tone && `tag--${tone}`)}>{children}</span>;
}

export function SkeletonRows({ count = 4, tall = false }: { count?: number; tall?: boolean }) {
  return (
    <div className="skeleton-list" aria-hidden="true">
      {Array.from({ length: count }).map((_, index) => (
        <div key={index} className={cx("skeleton-row", tall && "skeleton-row--tall")}>
          <div className="skeleton skeleton--avatar" />
          <div className="skeleton-row__lines">
            <div className="skeleton skeleton--title" style={{ width: `${52 + (index % 3) * 11}%` }} />
            <div className="skeleton skeleton--line" style={{ width: `${34 + (index % 2) * 18}%` }} />
          </div>
          <div className="skeleton skeleton--time" />
        </div>
      ))}
    </div>
  );
}

export function RecordingLink({
  recording,
  children,
  className,
}: {
  recording: RecordingSummary;
  children: ReactNode;
  className?: string;
}) {
  return (
    <Link to={`/recordings/${recording.id}`} className={className}>
      {children}
    </Link>
  );
}
