import { useEffect, useMemo, useState } from "react";
import {
  DownloadSimple,
  File as FileIcon,
  FileAudio,
  FileText,
  FileZip,
  FolderOpen,
  Image as ImageIcon,
  VideoCamera,
} from "@phosphor-icons/react";
import { Link } from "react-router-dom";
import { useApi, useDebounced, useRefreshEvent } from "../lib/hooks";
import type { FilesResponse, RecordingSummary } from "../types";
import { cx, formatBytes, formatRelative } from "../lib/format";
import {
  EmptyState,
  PageHead,
  PlayButton,
  SearchField,
  SkeletonRows,
  StatusPill,
  Tag,
  UploadButton,
} from "../components/ui";

type KindFilter = "" | "audio" | "document" | "image" | "video" | "archive";

function FileGlyph({ kind }: { kind: RecordingSummary["kind"] }) {
  const size = 18;
  if (kind === "call" || kind === "voice" || kind === "audio") return <FileAudio size={size} />;
  if (kind === "image") return <ImageIcon size={size} />;
  if (kind === "video") return <VideoCamera size={size} />;
  if (kind === "archive") return <FileZip size={size} />;
  if (kind === "document") return <FileText size={size} />;
  return <FileIcon size={size} />;
}

export function FilesPage() {
  const [kind, setKind] = useState<KindFilter>("");
  const [query, setQuery] = useState("");
  const debounced = useDebounced(query, 280);
  const path = useMemo(() => {
    const search = new URLSearchParams({ page: "1", page_size: "100" });
    if (kind) search.set("kind", kind);
    if (debounced.trim()) search.set("q", debounced.trim());
    return `/api/files?${search.toString()}`;
  }, [kind, debounced]);
  const { data, loading, error, reload } = useApi<FilesResponse>(path, { pollMs: 15000 });
  useRefreshEvent(reload);

  useEffect(() => {
    document.title = "文件库 · 声册";
  }, []);

  const counts = data?.kind_counts || {};
  const allCount = Object.values(counts).reduce((sum, value) => sum + value, 0);
  const chips: { value: KindFilter; label: string; count: number }[] = [
    { value: "", label: "全部", count: allCount },
    { value: "audio", label: "音频", count: (counts.call || 0) + (counts.voice || 0) + (counts.audio || 0) },
    { value: "document", label: "文档", count: (counts.document || 0) + (counts.other || 0) },
    { value: "image", label: "图片", count: counts.image || 0 },
    { value: "video", label: "视频", count: counts.video || 0 },
    { value: "archive", label: "压缩包", count: counts.archive || 0 },
  ];

  return (
    <div className="page">
      <PageHead
        title="文件库"
        description={
          <span className="page-head__meta">
            <span>手机上传的所有文件都放在这里</span>
            {data ? <span>共 {allCount} 个</span> : null}
          </span>
        }
        actions={<UploadButton />}
      />

      <div className="toolbar">
        <div className="segmented segmented--wrap" role="group" aria-label="文件类型">
          {chips.map((chip) => (
            <button
              key={chip.value || "all"}
              type="button"
              className={cx("segmented__item", kind === chip.value && "is-active")}
              onClick={() => setKind(chip.value)}
              aria-pressed={kind === chip.value}
            >
              {chip.label}
              {chip.count > 0 ? <span className="segmented__count mono">{chip.count}</span> : null}
            </button>
          ))}
        </div>
        <SearchField
          value={query}
          onChange={setQuery}
          placeholder="搜文件名或分类"
          label="搜索文件"
          className="toolbar__search"
        />
      </div>

      {error ? (
        <EmptyState
          title="文件库没有加载出来"
          action={<button type="button" className="btn btn--primary" onClick={reload}>再试一次</button>}
        >
          <p>{error}</p>
        </EmptyState>
      ) : null}

      {!error && loading && !data ? <SkeletonRows count={6} /> : null}

      {!error && !loading && data && data.items.length === 0 ? (
        <EmptyState
          icon={<FolderOpen size={26} />}
          title={query ? "没有找到文件" : "文件库还是空的"}
          action={
            query ? (
              <button type="button" className="btn btn--secondary" onClick={() => setQuery("")}>
                清空搜索
              </button>
            ) : (
              <UploadButton label="上传一个文件" />
            )
          }
        >
          <p>
            {query
              ? "试试文件名里的一个词。"
              : "录音、文档、图片和压缩包都可以上传。音频会额外整理出对话和摘要。"}
          </p>
        </EmptyState>
      ) : null}

      {data && data.items.length > 0 ? (
        <div className="file-table" role="table" aria-label="文件列表">
          <div className="file-table__head" role="row">
            <span role="columnheader">文件</span>
            <span role="columnheader">分类</span>
            <span role="columnheader">大小</span>
            <span role="columnheader">上传时间</span>
            <span role="columnheader">状态</span>
            <span role="columnheader"><span className="visually-hidden">操作</span></span>
          </div>
          {data.items.map((file) => {
            const isAudio = file.has_audio;
            return (
              <div className="file-row" role="row" key={file.id}>
                <div className="file-row__name" role="cell">
                  <span className={cx("file-row__glyph", `file-row__glyph--${file.kind}`)} aria-hidden="true">
                    <FileGlyph kind={file.kind} />
                  </span>
                  <div className="file-row__title-wrap">
                    {isAudio ? (
                      <Link to={`/recordings/${file.id}`} className="file-row__title">
                        {file.title || file.name}
                      </Link>
                    ) : (
                      <span className="file-row__title">{file.title || file.name}</span>
                    )}
                    <span className="file-row__name-small" title={file.name}>{file.name}</span>
                  </div>
                </div>
                <div className="file-row__category" role="cell">
                  <Tag>{file.category}</Tag>
                </div>
                <div className="file-row__size mono" role="cell">{formatBytes(file.size)}</div>
                <div className="file-row__time" role="cell">{formatRelative(file.uploaded_at)}</div>
                <div className="file-row__status" role="cell">
                  <StatusPill
                    status={file.status}
                    label={file.status_label}
                    stageLabel={file.stage_label}
                    error={file.error}
                    showReady
                  />
                </div>
                <div className="file-row__actions" role="cell">
                  {isAudio ? <PlayButton recording={file} size="sm" /> : null}
                  <a
                    href={`/api/recordings/${file.id}/download`}
                    className="icon-btn"
                    aria-label={`下载 ${file.name}`}
                    title="下载"
                  >
                    <DownloadSimple size={16} />
                  </a>
                </div>
              </div>
            );
          })}
        </div>
      ) : null}

      {data && data.items.length > 0 ? (
        <p className="page-footnote">
          同名文件被覆盖后会重新整理；分类来自文件类型和文件名，不会修改原文件。
        </p>
      ) : null}
    </div>
  );
}
