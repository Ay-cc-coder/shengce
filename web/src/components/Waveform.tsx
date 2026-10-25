import { useMemo } from "react";
import { cx, formatDuration } from "../lib/format";

function normalizePeaks(peaks: number[] | undefined, bars: number): number[] {
  if (!peaks || peaks.length === 0) {
    return Array.from({ length: bars }, (_, index) => 18 + Math.round(Math.abs(Math.sin(index * 0.45)) * 32));
  }
  if (peaks.length === bars) return peaks;
  return Array.from({ length: bars }, (_, index) => {
    const start = Math.floor((index / bars) * peaks.length);
    const end = Math.max(start + 1, Math.floor(((index + 1) / bars) * peaks.length));
    const slice = peaks.slice(start, end);
    return Math.round(slice.reduce((sum, value) => sum + value, 0) / Math.max(1, slice.length));
  });
}

export function Waveform({
  peaks,
  progress,
  currentTime = 0,
  duration = 0,
  onSeek,
  bars = 96,
  height = 68,
  dark = false,
  className,
  ariaLabel = "音频进度",
}: {
  peaks?: number[];
  progress: number;
  currentTime?: number;
  duration?: number;
  onSeek?: (time: number) => void;
  bars?: number;
  height?: number;
  dark?: boolean;
  className?: string;
  ariaLabel?: string;
}) {
  const heights = useMemo(() => normalizePeaks(peaks, bars), [peaks, bars]);
  const safeDuration = duration > 0 ? duration : 1;
  const value = Math.min(currentTime, safeDuration);
  const played = Math.min(bars, Math.round(progress * bars));

  return (
    <div
      className={cx(
        "waveform",
        dark && "waveform--dark",
        onSeek ? "waveform--interactive" : "waveform--static",
        className
      )}
      style={{ height }}
    >
      <div className="waveform__bars" aria-hidden="true">
        {heights.map((peak, index) => (
          <span
            key={index}
            className={cx("waveform__bar", index < played && "is-played")}
            style={{ height: `${Math.max(6, Math.round((peak / 100) * 100))}%` }}
          />
        ))}
      </div>
      {onSeek ? (
        <input
          className="waveform__range"
          type="range"
          min={0}
          max={safeDuration}
          step={0.1}
          value={value}
          onChange={(event) => onSeek(Number(event.target.value))}
          aria-label={ariaLabel}
          aria-valuetext={`${formatDuration(value)} / ${formatDuration(duration)}`}
        />
      ) : null}
    </div>
  );
}
