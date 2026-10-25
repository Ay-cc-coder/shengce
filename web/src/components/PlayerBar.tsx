import {
  ArrowClockwise,
  ArrowCounterClockwise,
  Pause,
  Play,
  X,
} from "@phosphor-icons/react";
import { Link, useLocation } from "react-router-dom";
import { usePlayer } from "../contexts";
import { cx, formatDuration, progressFor } from "../lib/format";
import { Avatar } from "./ui";
import { Waveform } from "./Waveform";

const RATES = [1, 1.25, 1.5, 2];

export function PlayerBar() {
  const player = usePlayer();
  const location = useLocation();
  const track = player.track;
  if (!track) return null;
  if (location.pathname === `/recordings/${track.id}`) return null;

  const progress = progressFor(player.time, player.duration || track.duration || 0);
  const nextRate = RATES[(RATES.indexOf(player.rate) + 1) % RATES.length];

  return (
    <div className="player-bar" role="region" aria-label="正在播放">
      <div className="player-bar__inner">
        <div className="player-bar__track">
          <Avatar contact={track.contact} name={track.contact?.name || "我"} size="sm" />
          <div className="player-bar__meta">
            <Link to={`/recordings/${track.id}`} className="player-bar__title">
              {track.title}
            </Link>
            <span className="player-bar__sub">
              {track.contact?.name || (track.kind === "voice" ? "语音备忘" : "录音")}
              {player.error ? <span className="player-bar__error">{player.error}</span> : null}
            </span>
          </div>
        </div>

        <div className="player-bar__center">
          <Waveform
            peaks={track.waveform}
            progress={progress}
            currentTime={player.time}
            duration={player.duration || track.duration || 0}
            onSeek={player.seek}
            bars={72}
            height={34}
            dark
            ariaLabel="播放进度"
          />
          <div className="player-bar__times mono" aria-hidden="true">
            <span>{formatDuration(player.time)}</span>
            <span>{formatDuration(player.duration || track.duration)}</span>
          </div>
        </div>

        <div className="player-bar__controls">
          <button
            type="button"
            className="icon-btn icon-btn--dark player-bar__skip"
            onClick={() => player.seek(Math.max(0, player.time - 15))}
            aria-label="后退 15 秒"
            title="后退 15 秒"
          >
            <ArrowCounterClockwise size={17} />
          </button>
          <button
            type="button"
            className="player-bar__play"
            onClick={() => {
              if (player.playing) player.pause();
              else player.play(track);
            }}
            aria-label={player.playing ? "暂停" : "播放"}
          >
            {player.playing ? <Pause size={20} weight="fill" /> : <Play size={20} weight="fill" />}
          </button>
          <button
            type="button"
            className="icon-btn icon-btn--dark player-bar__skip"
            onClick={() => player.seek(Math.min(player.duration || track.duration || 0, player.time + 30))}
            aria-label="前进 30 秒"
            title="前进 30 秒"
          >
            <ArrowClockwise size={17} />
          </button>
          <button
            type="button"
            className={cx("player-bar__rate", "mono")}
            onClick={() => player.setRate(nextRate)}
            aria-label={`切换播放速度，当前 ${player.rate} 倍`}
          >
            {player.rate}x
          </button>
          <button
            type="button"
            className="icon-btn icon-btn--dark player-bar__close"
            onClick={player.close}
            aria-label="关闭播放器"
            title="关闭"
          >
            <X size={17} />
          </button>
        </div>
      </div>
    </div>
  );
}
