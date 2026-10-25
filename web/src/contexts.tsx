import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { api } from "./lib/api";
import type { Contact } from "./types";

/* ----------------------------- auth ----------------------------- */

interface AuthState {
  authenticated: boolean;
  loading: boolean;
  demoMode: boolean;
  llmEnabled: boolean;
  version: string;
  error: string | null;
  login: (password: string) => Promise<void>;
  logout: () => Promise<void>;
  refresh: () => void;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [authenticated, setAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);
  const [demoMode, setDemoMode] = useState(false);
  const [llmEnabled, setLlmEnabled] = useState(false);
  const [version, setVersion] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    api
      .get<{
        authenticated: boolean;
        demo_mode: boolean;
        llm_enabled: boolean;
        version: string;
      }>("/api/auth/status", controller.signal)
      .then((status) => {
        setAuthenticated(status.authenticated);
        setDemoMode(status.demo_mode);
        setLlmEnabled(status.llm_enabled);
        setVersion(status.version);
        setError(null);
      })
      .catch((err) => {
        if (err instanceof DOMException && err.name === "AbortError") return;
        setError("无法连接服务器。");
        setAuthenticated(false);
      })
      .finally(() => setLoading(false));
    return () => controller.abort();
  }, [refreshKey]);

  useEffect(() => {
    const handler = () => setAuthenticated(false);
    window.addEventListener("shengce:unauthorized", handler);
    return () => window.removeEventListener("shengce:unauthorized", handler);
  }, []);

  const login = useCallback(async (password: string) => {
    await api.post<{ authenticated: boolean }>("/api/auth/login", { password });
    setAuthenticated(true);
    setError(null);
  }, []);

  const logout = useCallback(async () => {
    try {
      await api.post("/api/auth/logout");
    } finally {
      setAuthenticated(false);
    }
  }, []);

  const refresh = useCallback(() => setRefreshKey((value) => value + 1), []);

  const value = useMemo<AuthState>(
    () => ({
      authenticated,
      loading,
      demoMode,
      llmEnabled,
      version,
      error,
      login,
      logout,
      refresh,
    }),
    [authenticated, loading, demoMode, llmEnabled, version, error, login, logout, refresh]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const value = useContext(AuthContext);
  if (!value) throw new Error("useAuth must be used inside AuthProvider");
  return value;
}

/* ----------------------------- toast ----------------------------- */

type ToastTone = "default" | "success" | "error";
interface ToastItem {
  id: number;
  message: string;
  tone: ToastTone;
}
interface ToastState {
  show: (message: string, tone?: ToastTone) => void;
}
const ToastContext = createContext<ToastState | null>(null);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([]);
  const counter = useRef(0);

  const show = useCallback((message: string, tone: ToastTone = "default") => {
    counter.current += 1;
    const id = counter.current;
    setItems((current) => [...current.slice(-2), { id, message, tone }]);
    window.setTimeout(() => {
      setItems((current) => current.filter((item) => item.id !== id));
    }, 4200);
  }, []);

  const value = useMemo(() => ({ show }), [show]);

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div className="toast-stack" role="status" aria-live="polite">
        {items.map((item) => (
          <div key={item.id} className={`toast toast--${item.tone}`}>
            {item.message}
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastState {
  const value = useContext(ToastContext);
  if (!value) throw new Error("useToast must be used inside ToastProvider");
  return value;
}

/* ----------------------------- player ----------------------------- */

export interface PlayerTrack {
  id: string;
  title: string;
  kind: string;
  src: string;
  duration: number | null;
  contact: Contact | null;
  waveform: number[];
}

interface PlayerState {
  track: PlayerTrack | null;
  playing: boolean;
  time: number;
  duration: number;
  rate: number;
  error: string | null;
  toggle: (track: PlayerTrack, startAt?: number) => void;
  play: (track: PlayerTrack, startAt?: number) => void;
  pause: () => void;
  seek: (time: number) => void;
  seekCurrent: (time: number) => void;
  setRate: (rate: number) => void;
  close: () => void;
  isCurrent: (id: string) => boolean;
}

const PlayerContext = createContext<PlayerState | null>(null);

export function PlayerProvider({ children }: { children: ReactNode }) {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [track, setTrack] = useState<PlayerTrack | null>(null);
  const [playing, setPlaying] = useState(false);
  const [time, setTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [rate, setRateState] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const pendingSeek = useRef<number | null>(null);
  const played = useRef<Set<string>>(new Set());
  const trigger = useRef<HTMLElement | null>(null);

  const markPlayed = useCallback((id: string) => {
    if (played.current.has(id)) return;
    played.current.add(id);
    api.post(`/api/recordings/${id}/played`).catch(() => undefined);
  }, []);

  const start = useCallback(
    (next: PlayerTrack, startAt?: number) => {
      const audio = audioRef.current;
      if (!audio) return;
      setError(null);
      const isNew = track?.id !== next.id;
      if (isNew) {
        if (document.activeElement instanceof HTMLElement) {
          trigger.current = document.activeElement;
        }
        setTrack(next);
        setTime(startAt ?? 0);
        setDuration(next.duration ?? 0);
        pendingSeek.current = startAt ?? null;
        audio.src = next.src;
        audio.load();
      } else if (startAt !== undefined) {
        audio.currentTime = startAt;
        setTime(startAt);
      }
      audio.playbackRate = rate;
      audio
        .play()
        .then(() => {
          setPlaying(true);
          markPlayed(next.id);
        })
        .catch(() => {
          setPlaying(false);
          setError("浏览器阻止了自动播放，请再点一次播放键。");
        });
    },
    [markPlayed, rate, track?.id]
  );

  const toggle = useCallback(
    (next: PlayerTrack, startAt?: number) => {
      const audio = audioRef.current;
      if (!audio) return;
      if (track?.id === next.id) {
        if (audio.paused) {
          audio
            .play()
            .then(() => {
              setPlaying(true);
              markPlayed(next.id);
            })
            .catch(() => setError("浏览器阻止了播放，请再点一次播放键。"));
        } else {
          audio.pause();
          setPlaying(false);
        }
      } else {
        start(next, startAt);
      }
    },
    [markPlayed, start, track?.id]
  );

  const pause = useCallback(() => {
    audioRef.current?.pause();
    setPlaying(false);
  }, []);

  const seek = useCallback((value: number) => {
    const audio = audioRef.current;
    if (!audio) return;
    const clamped = Math.max(0, Math.min(value, audio.duration || duration || value));
    audio.currentTime = clamped;
    setTime(clamped);
  }, [duration]);

  const setRate = useCallback((value: number) => {
    setRateState(value);
    if (audioRef.current) audioRef.current.playbackRate = value;
  }, []);

  const close = useCallback(() => {
    const audio = audioRef.current;
    if (audio) {
      audio.pause();
      audio.removeAttribute("src");
      audio.load();
    }
    setTrack(null);
    setPlaying(false);
    setTime(0);
    setDuration(0);
    setError(null);
    const previous = trigger.current;
    trigger.current = null;
    if (previous && document.contains(previous)) {
      previous.focus({ preventScroll: true });
    }
  }, []);

  const isCurrent = useCallback((id: string) => track?.id === id, [track?.id]);

  useEffect(() => {
    return () => {
      audioRef.current?.pause();
    };
  }, []);

  const value = useMemo<PlayerState>(
    () => ({
      track,
      playing,
      time,
      duration,
      rate,
      error,
      toggle,
      play: start,
      pause,
      seek,
      seekCurrent: seek,
      setRate,
      close,
      isCurrent,
    }),
    [track, playing, time, duration, rate, error, toggle, start, pause, seek, setRate, close, isCurrent]
  );

  return (
    <PlayerContext.Provider value={value}>
      {children}
      <audio
        ref={audioRef}
        preload="metadata"
        onTimeUpdate={(event) => setTime(event.currentTarget.currentTime)}
        onLoadedMetadata={(event) => {
          const audio = event.currentTarget;
          setDuration(Number.isFinite(audio.duration) ? audio.duration : 0);
          if (pendingSeek.current !== null) {
            const target = Math.min(pendingSeek.current, audio.duration || pendingSeek.current);
            audio.currentTime = target;
            setTime(target);
            pendingSeek.current = null;
          }
        }}
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
        onEnded={(event) => {
          setPlaying(false);
          setTime(event.currentTarget.duration || 0);
        }}
        onError={() => {
          setPlaying(false);
          setError("这段音频无法播放，文件可能已被移动。");
        }}
        aria-hidden="true"
        className="player-audio"
      />
    </PlayerContext.Provider>
  );
}

export function usePlayer(): PlayerState {
  const value = useContext(PlayerContext);
  if (!value) throw new Error("usePlayer must be used inside PlayerProvider");
  return value;
}
