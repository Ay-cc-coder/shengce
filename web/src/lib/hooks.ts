import { useCallback, useEffect, useRef, useState } from "react";
import { api, isAbort } from "../lib/api";

interface UseApiOptions {
  pollMs?: number;
  enabled?: boolean;
}

export function useApi<T>(path: string | null, options: UseApiOptions = {}) {
  const { pollMs = 0, enabled = true } = options;
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(Boolean(path) && enabled);
  const [error, setError] = useState<string | null>(null);
  const [version, setVersion] = useState(0);
  const mounted = useRef(true);

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  useEffect(() => {
    if (!path || !enabled) {
      setLoading(false);
      return;
    }
    const controller = new AbortController();
    let timer: number | undefined;

    const load = async (quiet = false) => {
      if (!quiet) setLoading(true);
      try {
        const payload = await api.get<T>(path, controller.signal);
        if (!mounted.current) return;
        setData(payload);
        setError(null);
      } catch (err) {
        if (isAbort(err)) return;
        if (!mounted.current) return;
        setError(err instanceof Error ? err.message : "加载失败。");
      } finally {
        if (mounted.current && !quiet) setLoading(false);
      }
    };

    void load();
    if (pollMs > 0) {
      timer = window.setInterval(() => void load(true), pollMs);
    }
    return () => {
      controller.abort();
      if (timer) window.clearInterval(timer);
    };
  }, [path, enabled, pollMs, version]);

  const reload = useCallback(() => setVersion((value) => value + 1), []);
  return { data, loading, error, reload, setData };
}

export function useRefreshEvent(callback: () => void): void {
  const handler = useRef(callback);
  handler.current = callback;
  useEffect(() => {
    const listener = () => handler.current();
    window.addEventListener("shengce:refresh", listener);
    return () => window.removeEventListener("shengce:refresh", listener);
  }, []);
}

export function useDebounced<T>(value: T, delay = 280): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = window.setTimeout(() => setDebounced(value), delay);
    return () => window.clearTimeout(timer);
  }, [value, delay]);
  return debounced;
}

export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(() =>
    typeof window !== "undefined" ? window.matchMedia(query).matches : false
  );
  useEffect(() => {
    const media = window.matchMedia(query);
    const listener = () => setMatches(media.matches);
    listener();
    media.addEventListener("change", listener);
    return () => media.removeEventListener("change", listener);
  }, [query]);
  return matches;
}
