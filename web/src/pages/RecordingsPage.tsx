import { useEffect, useMemo, useState } from "react";
import { ArrowRight, Waveform as WaveformIcon } from "@phosphor-icons/react";
import { Link, useSearchParams } from "react-router-dom";
import { useApi, useDebounced, useRefreshEvent } from "../lib/hooks";
import type { Paged, RecordingSummary } from "../types";
import { cx, dateKey, formatDayHeading } from "../lib/format";
import {
  EmptyState,
  PageHead,
  SearchField,
  SkeletonRows,
  UploadButton,
} from "../components/ui";
import { RecordingRow } from "../components/RecordingRow";

export function RecordingsPage() {
  const [params, setParams] = useSearchParams();
  const contactId = params.get("contact") || "";
  const contactName = params.get("contactName") || "";
  const [category, setCategory] = useState("");
  const [query, setQuery] = useState("");
  const debouncedQuery = useDebounced(query, 280);
  const [page, setPage] = useState(1);
  const [items, setItems] = useState<RecordingSummary[]>([]);

  const path = useMemo(() => {
    const search = new URLSearchParams();
    search.set("page", String(page));
    search.set("page_size", "20");
    if (category) search.set("category", category);
    if (contactId) search.set("contact_id", contactId);
    if (debouncedQuery.trim()) search.set("q", debouncedQuery.trim());
    return `/api/recordings?${search.toString()}`;
  }, [page, category, contactId, debouncedQuery]);

  const { data, loading, error, reload } = useApi<Paged<RecordingSummary>>(path, {
    pollMs: 12000,
  });
  useRefreshEvent(reload);

  useEffect(() => {
    document.title = "录音 · 声册";
  }, []);

  useEffect(() => {
    setPage(1);
    setItems([]);
  }, [category, contactId, debouncedQuery]);

  useEffect(() => {
    if (!data) return;
    setItems((current) => {
      if (page === 1) return data.items;
      const seen = new Set(current.map((item) => item.id));
      return [...current, ...data.items.filter((item) => !seen.has(item.id))];
    });
  }, [data, page]);

  const groups = useMemo(() => {
    const map = new Map<string, RecordingSummary[]>();
    for (const item of items) {
      const key = dateKey(item.recorded_at);
      const list = map.get(key) ?? [];
      list.push(item);
      map.set(key, list);
    }
    return Array.from(map.entries());
  }, [items]);

  const handleQueryChange = (value: string) => {
    setQuery(value);
    // Searching is global: don't keep a stale direction/type filter that
    // hides matching calls (e.g. searching 老妈 while 语音备忘 is selected).
    if (value.trim() && category) {
      setCategory("");
    }
  };

  const clearContact = () => {
    const next = new URLSearchParams(params);
    next.delete("contact");
    next.delete("contactName");
    setParams(next, { replace: true });
    setPage(1);
    setItems([]);
  };

  return (
    <div className="page">
      <PageHead
        title="录音"
        description={
          <span className="page-head__meta">
            <span>{contactName ? `与 ${contactName} 的通话` : "按时间回听，转写和待办都在里面"}</span>
            {data ? <span>共 {data.total} 段</span> : null}
          </span>
        }
        actions={<UploadButton />}
      />

      <div className="toolbar">
        <div className="segmented segmented--small segmented--wrap" role="group" aria-label="录音分类">
          {(
            [
              ["", "全部"],
              ["呼入", "呼入"],
              ["呼出", "呼出"],
              ["语音备忘", "语音备忘"],
            ] as const
          ).map(([value, label]) => (
            <button
              key={value || "all"}
              type="button"
              className={cx("segmented__item", category === value && "is-active")}
              onClick={() => setCategory(value)}
              aria-pressed={category === value}
            >
              {label}
            </button>
          ))}
        </div>
        <SearchField
          value={query}
          onChange={handleQueryChange}
          placeholder="搜标题、联系人或对话"
          label="搜索录音"
          className="toolbar__search"
        />
        {contactId ? (
          <button type="button" className="filter-chip" onClick={clearContact}>
            只看 {contactName || "这个联系人"}
            <span aria-hidden="true">×</span>
          </button>
        ) : null}
      </div>

      {error ? (
        <EmptyState
          title="录音列表没有加载出来"
          action={<button type="button" className="btn btn--primary" onClick={reload}>再试一次</button>}
        >
          <p>{error}</p>
        </EmptyState>
      ) : null}

      {!error && loading && items.length === 0 ? <SkeletonRows count={6} tall /> : null}

      {!error && !loading && items.length === 0 ? (
        <EmptyState
          icon={<WaveformIcon size={26} />}
          title={query ? "没有找到匹配的录音" : "还没有录音"}
          action={
            query ? (
              <button type="button" className="btn btn--secondary" onClick={() => setQuery("")}>
                清空搜索
              </button>
            ) : (
              <UploadButton label="上传一段" />
            )
          }
        >
          <p>
            {query
              ? "试试更短的关键词，或按联系人和类型筛选。"
              : "手机上传或手动上传的音频会出现在这里，处理完成后可以看对话和摘要。"}
          </p>
        </EmptyState>
      ) : null}

      <div className="rec-groups">
        {groups.map(([key, rows]) => (
          <section className="rec-group" key={key}>
            <h2 className="rec-group__heading">{formatDayHeading(rows[0].recorded_at)}</h2>
            <div className="rec-list">
              {rows.map((recording) => (
                <RecordingRow key={recording.id} recording={recording} />
              ))}
            </div>
          </section>
        ))}
      </div>

      {data && page < data.pages ? (
        <div className="load-more">
          <button
            type="button"
            className="btn btn--secondary"
            onClick={() => setPage((value) => value + 1)}
            disabled={loading}
          >
            {loading ? "正在加载" : "加载更多"}
            <ArrowRight size={15} aria-hidden="true" />
          </button>
          <span className="muted">已显示 {items.length} / {data.total}</span>
        </div>
      ) : null}

      {!loading && items.length > 0 ? (
        <p className="page-footnote">
          自动转写与说话人分段可能有误。重要内容请以原话为准。
          <Link to="/setup" className="inline-link">查看整理说明</Link>
        </p>
      ) : null}
    </div>
  );
}
