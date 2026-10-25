import { useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowClockwise,
  ArrowCounterClockwise,
  ArrowLeft,
  CaretDown,
  Check,
  Copy,
  DownloadSimple,
  FileAudio,
  PencilSimple,
  Play,
  Pause,
  ArrowsClockwise,
  Headphones,
} from "@phosphor-icons/react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { api } from "../lib/api";
import { useApi, useRefreshEvent } from "../lib/hooks";
import { usePlayer, useToast } from "../contexts";
import type { ContactsResponse, RecordingDetail } from "../types";
import {
  cx,
  formatBytes,
  formatDateTime,
  formatDuration,
  formatMonthDay,
  progressFor,
  weekdayName,
} from "../lib/format";
import {
  Avatar,
  EmptyState,
  SkeletonRows,
  StatusPill,
  Tag,
} from "../components/ui";
import { ActionRow } from "../components/ActionRow";
import { ChatTranscript } from "../components/ChatTranscript";
import { Waveform } from "../components/Waveform";

const RATES = [1, 1.25, 1.5, 2];

function fullDate(value: string) {
  const date = new Date(value);
  const now = new Date();
  const year = date.getFullYear() === now.getFullYear() ? "" : `${date.getFullYear()}年`;
  return `${year}${formatMonthDay(date)} ${weekdayName(date)} ${formatDateTime(date).split(" ")[1]}`;
}

export function RecordingPage() {
  const { id = "" } = useParams();
  const [params] = useSearchParams();
  const toast = useToast();
  const player = usePlayer();
  const [focusIdx, setFocusIdx] = useState<number | null>(null);
  const [speakerOpen, setSpeakerOpen] = useState(false);
  const [contactOpen, setContactOpen] = useState(false);
  const [names, setNames] = useState<Record<string, string>>({});
  const [contactName, setContactName] = useState("");
  const [saving, setSaving] = useState(false);
  const [reprocessing, setReprocessing] = useState(false);
  const applied = useRef<string | null>(null);

  const { data, loading, error, reload, setData } = useApi<RecordingDetail>(
    id ? `/api/recordings/${id}` : null
  );
  useRefreshEvent(reload);

  useEffect(() => {
    if (!data || data.status === "ready" || data.status === "failed") return;
    const timer = window.setInterval(reload, 3000);
    return () => window.clearInterval(timer);
  }, [data?.status, reload]);
  const contactsQuery = useApi<ContactsResponse>(contactOpen ? "/api/contacts" : null);

  useEffect(() => {
    if (data) document.title = `${data.title} · 声册`;
  }, [data]);

  useEffect(() => {
    if (!data) return;
    setNames(data.speakers || {});
    setContactName(data.contact?.name || "");
  }, [data?.id]);

  useEffect(() => {
    if (!data) return;
    const raw = params.get("t");
    const key = `${data.id}:${raw ?? ""}`;
    if (applied.current === key) return;
    if (raw !== null) {
      const seconds = Number(raw);
      if (Number.isFinite(seconds)) {
        const segment = data.segments.find(
          (item) => seconds >= item.start && seconds < item.end + 0.5
        );
        if (segment) {
          setFocusIdx(segment.idx);
          applied.current = key;
          return;
        }
      }
    }
    applied.current = key;
  }, [data, params]);

  const track = useMemo(() => {
    if (!data) return null;
    return {
      id: data.id,
      title: data.title,
      kind: data.kind,
      src: data.audio_url || `/api/recordings/${data.id}/audio`,
      duration: data.duration,
      contact: data.contact,
      waveform: data.waveform || [],
    };
  }, [data]);

  if (loading && !data) {
    return (
      <div className="page">
        <Link to="/recordings" className="back-link">
          <ArrowLeft size={16} aria-hidden="true" />
          录音
        </Link>
        <SkeletonRows count={5} tall />
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="page">
        <Link to="/recordings" className="back-link">
          <ArrowLeft size={16} aria-hidden="true" />
          录音
        </Link>
        <EmptyState
          title="这段录音没有找到"
          action={
            <Link to="/recordings" className="btn btn--primary">
              回到录音列表
            </Link>
          }
        >
          <p>{error || "它可能已经从资料库里移除了。"}</p>
        </EmptyState>
      </div>
    );
  }

  const isCurrent = track ? player.isCurrent(data.id) : false;
  const playing = isCurrent && player.playing;
  const currentTime = isCurrent ? player.time : 0;
  const duration = (isCurrent ? player.duration : 0) || data.duration || 0;
  const progress = isCurrent ? progressFor(player.time, duration) : 0;
  const focusStart =
    focusIdx !== null ? data.segments.find((item) => item.idx === focusIdx)?.start : undefined;
  const stageOrder = ["waiting", "reading", "classifying", "transcribing", "organizing", "done"];
  const stageIndex = Math.max(0, stageOrder.indexOf(data.stage));
  const steps = [
    { label: "读取音频", done: stageIndex > 1, active: stageIndex <= 1 },
    { label: "转写对话", done: stageIndex > 3, active: stageIndex === 2 || stageIndex === 3 },
    { label: "整理摘要", done: stageIndex > 4, active: stageIndex === 4 },
  ];

  const startPlayback = (at?: number) => {
    if (!track) return;
    if (!isCurrent) {
      player.play(track, at ?? focusStart ?? 0);
    } else if (player.playing) {
      player.pause();
    } else {
      player.play(track);
    }
  };

  const seek = (time: number) => {
    if (!track) return;
    if (isCurrent) player.seek(time);
    else player.play(track, time);
  };

  const chatSeek = (time: number) => {
    if (!track) return;
    player.play(track, time);
    const segment = data.segments.find((item) => time >= item.start && time < item.end + 0.5);
    if (segment) setFocusIdx(segment.idx);
  };

  const changeAction = (action: (typeof data.actions)[number], done: boolean) => {
    setData((current) => {
      if (!current) return current;
      const actions = current.actions.map((item) =>
        item.id === action.id ? { ...item, done } : item
      );
      return {
        ...current,
        actions,
        action_open: actions.filter((item) => !item.done).length,
      };
    });
  };

  const saveSpeakers = async () => {
    setSaving(true);
    try {
      const updated = await api.patch<RecordingDetail>(`/api/recordings/${data.id}/speakers`, {
        names,
      });
      setData(updated);
      setSpeakerOpen(false);
      toast.show("说话人已更新。", "success");
      window.dispatchEvent(new Event("shengce:refresh"));
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "保存失败。", "error");
    } finally {
      setSaving(false);
    }
  };

  const saveContact = async () => {
    setSaving(true);
    try {
      const updated = await api.patch<RecordingDetail>(`/api/recordings/${data.id}`, {
        contact_name: contactName,
      });
      setData(updated);
      setContactOpen(false);
      toast.show("联系人已更新。", "success");
      window.dispatchEvent(new Event("shengce:refresh"));
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "保存失败。", "error");
    } finally {
      setSaving(false);
    }
  };

  const reprocess = async () => {
    setReprocessing(true);
    try {
      await api.post(`/api/recordings/${data.id}/reprocess`);
      toast.show("已重新排队，稍后刷新结果。", "success");
      reload();
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "重新处理失败。", "error");
    } finally {
      setReprocessing(false);
    }
  };

  const copyTranscript = async () => {
    const text = data.segments
      .map((segment) => {
        const name = data.speakers[segment.speaker] || segment.speaker_name;
        return `[${formatDuration(segment.start)}] ${name}: ${segment.text}`;
      })
      .join("\n");
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      toast.show("对话全文已复制。", "success");
    } catch {
      toast.show("浏览器不允许复制，请手动选择文本。", "error");
    }
  };

  const speakerKeys = Object.keys(data.speakers || {});
  const sourceNote =
    data.analysis_source === "demo"
      ? "演示数据"
      : data.analysis_source === "llm"
        ? `由 ${data.model || "模型"} 整理`
        : data.analysis_source === "hybrid"
          ? "模型与本地规则共同整理"
          : "本机规则整理";

  return (
    <div className="page page--recording">
      <Link to="/recordings" className="back-link">
        <ArrowLeft size={16} aria-hidden="true" />
        录音
      </Link>

      <header className="recording-head">
        <div className="recording-head__identity">
          <Avatar contact={data.contact} name={data.contact?.name || "我"} size="xl" />
          <div className="recording-head__text">
            <div className="recording-head__meta">
              <span>{data.kind_label}</span>
              {data.contact ? (
                <button
                  type="button"
                  className="recording-head__contact"
                  onClick={() => setContactOpen((value) => !value)}
                >
                  {data.contact.name}
                  <PencilSimple size={12} aria-hidden="true" />
                </button>
              ) : data.kind === "voice" ? (
                <span>单人录音</span>
              ) : (
                <button
                  type="button"
                  className="recording-head__contact"
                  onClick={() => setContactOpen((value) => !value)}
                >
                  未识别联系人
                  <PencilSimple size={12} aria-hidden="true" />
                </button>
              )}
              <span className="mono">{fullDate(data.recorded_at)}</span>
            </div>
            <h1>{data.title}</h1>
            <div className="recording-head__facts">
              <span>{formatDuration(data.duration)}</span>
              <span>{formatBytes(data.size)}</span>
              <StatusPill
                status={data.status}
                label={data.status_label}
                stageLabel={data.stage_label}
                error={data.error}
                showReady
              />
              {data.action_open > 0 ? <Tag>{data.action_open} 件待办</Tag> : null}
            </div>
          </div>
        </div>
        <div className="recording-head__actions">
          <a
            className="btn btn--ghost btn--small"
            href={`/api/recordings/${data.id}/download`}
            aria-label="下载原始文件"
          >
            <DownloadSimple size={16} aria-hidden="true" />
            下载
          </a>
          <button
            type="button"
            className="btn btn--ghost btn--small"
            onClick={() => void reprocess()}
            disabled={reprocessing}
          >
            <ArrowsClockwise size={16} aria-hidden="true" />
            {reprocessing ? "已排队" : "重新整理"}
          </button>
        </div>
      </header>

      {contactOpen ? (
        <div className="inline-panel">
          <label className="field">
            <span className="field__label">归到联系人</span>
            <input
              value={contactName}
              onChange={(event) => setContactName(event.target.value)}
              placeholder="输入联系人名字"
              list="contact-suggestions"
              autoFocus
            />
            <datalist id="contact-suggestions">
              {contactsQuery.data?.items.map((item) => (
                <option key={item.contact.id} value={item.contact.name} />
              ))}
            </datalist>
          </label>
          <div className="inline-panel__actions">
            <button type="button" className="btn btn--primary btn--small" onClick={() => void saveContact()} disabled={saving}>
              保存
            </button>
            <button type="button" className="btn btn--ghost btn--small" onClick={() => setContactOpen(false)}>
              取消
            </button>
          </div>
        </div>
      ) : null}

      <section className={cx("recorder", data.status === "failed" && "recorder--failed")} aria-label="录音播放">
        <div className="recorder__play">
          <button
            type="button"
            className="recorder__button"
            onClick={() => startPlayback()}
            disabled={!data.has_audio}
            aria-label={playing ? "暂停" : `播放 ${data.title}`}
          >
            {playing ? <Pause size={26} weight="fill" /> : <Play size={26} weight="fill" />}
          </button>
          <div className="recorder__time mono">
            <span>{formatDuration(currentTime)}</span>
            <span className="recorder__time-total">{formatDuration(duration)}</span>
          </div>
        </div>
        <div className="recorder__wave">
          <Waveform
            peaks={data.waveform}
            progress={progress}
            currentTime={currentTime}
            duration={duration}
            onSeek={seek}
            bars={120}
            height={96}
            dark
          />
        </div>
        <div className="recorder__controls">
          <button
            type="button"
            className="icon-btn icon-btn--dark"
            onClick={() => seek(Math.max(0, currentTime - 15))}
            aria-label="后退 15 秒"
            title="后退 15 秒"
          >
            <ArrowCounterClockwise size={18} />
          </button>
          <button
            type="button"
            className="icon-btn icon-btn--dark"
            onClick={() => seek(Math.min(duration, currentTime + 30))}
            aria-label="前进 30 秒"
            title="前进 30 秒"
          >
            <ArrowClockwise size={18} />
          </button>
          <button
            type="button"
            className="recorder__rate mono"
            onClick={() => {
              const next = RATES[(RATES.indexOf(player.rate) + 1) % RATES.length];
              player.setRate(next);
            }}
            aria-label={`切换播放速度，当前 ${player.rate} 倍`}
          >
            {player.rate}x
          </button>
        </div>
      </section>
      {player.error && isCurrent ? <p className="form-error">{player.error}</p> : null}

      {data.status === "processing" || data.status === "queued" ? (
        <section className="processing" role="status">
          <div className="processing__head">
            <span className="dot dot--amber" aria-hidden="true" />
            <strong>{data.stage_label}</strong>
            <span>文件已经收好，整理完成后会自动刷新。</span>
          </div>
          <div className="processing__steps">
            {steps.map((step, index) => (
              <div
                key={step.label}
                className={cx(
                  "processing__step",
                  step.active && "is-active",
                  step.done && "is-done"
                )}
              >
                <span className="processing__dot" aria-hidden="true">
                  {step.done ? <Check size={12} /> : index + 1}
                </span>
                {step.label}
              </div>
            ))}
          </div>
        </section>
      ) : null}

      {data.status === "failed" ? (
        <section className="failure-panel" role="alert">
          <div>
            <strong>这段录音没有整理完成</strong>
            <p>{data.error || "可以重新整理一次。"}</p>
          </div>
          <button type="button" className="btn btn--primary btn--small" onClick={() => void reprocess()}>
            重新整理
          </button>
        </section>
      ) : null}

      <div className="recording-layout">
        <div className="recording-main">
          <section className="section transcript-section" aria-label="录音对话">
            <div className="section-heading">
              <h2>对话</h2>
              <span className="section-count">{data.segments.length} 段</span>
              <div className="section-heading__spacer" />
              {data.speaker_mode === "auto" && data.kind === "call" ? (
                <span className="soft-note">自动分段</span>
              ) : null}
              <button
                type="button"
                className="btn btn--ghost btn--small"
                onClick={() => setSpeakerOpen((value) => !value)}
                aria-expanded={speakerOpen}
              >
                <PencilSimple size={15} aria-hidden="true" />
                说话人
                <CaretDown size={13} aria-hidden="true" />
              </button>
              <button
                type="button"
                className="icon-btn"
                onClick={() => void copyTranscript()}
                aria-label="复制对话全文"
                title="复制对话全文"
                disabled={!data.segments.length}
              >
                <Copy size={17} />
              </button>
            </div>

            {speakerOpen ? (
              <div className="speaker-panel">
                <p className="speaker-panel__hint">
                  自动分段只根据停顿交替，可能把双方认反。改名或交换后，对话会按新名字显示。
                </p>
                <div className="speaker-panel__fields">
                  {speakerKeys.map((key) => (
                    <label className="field" key={key}>
                      <span className="field__label">
                        {key === "1" ? "左侧说话人" : key === "2" ? "右侧说话人" : "说话人"}
                      </span>
                      <input
                        value={names[key] || ""}
                        onChange={(event) =>
                          setNames((current) => ({ ...current, [key]: event.target.value }))
                        }
                        maxLength={20}
                      />
                    </label>
                  ))}
                </div>
                <div className="speaker-panel__actions">
                  {speakerKeys.includes("1") && speakerKeys.includes("2") ? (
                    <button
                      type="button"
                      className="btn btn--ghost btn--small"
                      onClick={() =>
                        setNames((current) => ({
                          ...current,
                          "1": current["2"],
                          "2": current["1"],
                        }))
                      }
                    >
                      交换左右
                    </button>
                  ) : null}
                  <button
                    type="button"
                    className="btn btn--primary btn--small"
                    onClick={() => void saveSpeakers()}
                    disabled={saving}
                  >
                    保存
                  </button>
                  <button
                    type="button"
                    className="btn btn--ghost btn--small"
                    onClick={() => {
                      setNames(data.speakers);
                      setSpeakerOpen(false);
                    }}
                  >
                    取消
                  </button>
                </div>
              </div>
            ) : null}

            {data.status === "ready" ? (
              <ChatTranscript
                recording={data}
                currentTime={isCurrent ? player.time : -1}
                focusIdx={focusIdx}
                onSeek={chatSeek}
              />
            ) : data.status === "failed" ? (
              <EmptyState
                compact
                icon={<FileAudio size={24} />}
                title="转写没有完成"
                action={
                  <button type="button" className="btn btn--secondary btn--small" onClick={() => void reprocess()}>
                    再试一次
                  </button>
                }
              >
                <p>原始音频还在，重新整理不会删除文件。</p>
              </EmptyState>
            ) : (
              <div className="transcript-wait">
                <p>正在整理对话，页面会自动刷新。</p>
              </div>
            )}
          </section>
        </div>

        <aside className="recording-rail">
          <section className="rail-section">
            <div className="section-heading section-heading--tight">
              <h2>摘要</h2>
              <span className="rail-source">{sourceNote}</span>
            </div>
            {data.summary ? (
              <p className="summary-text">{data.summary}</p>
            ) : (
              <p className="muted">摘要还在生成。</p>
            )}
            {data.key_points.length ? (
              <ul className="key-points">
                {data.key_points.map((point, index) => (
                  <li key={index}>{point}</li>
                ))}
              </ul>
            ) : null}
            {data.topics.length ? (
              <div className="tag-row">
                {data.topics.map((topic) => (
                  <Tag key={topic}>{topic}</Tag>
                ))}
              </div>
            ) : null}
            <p className="rail-note">
              自动整理可能有误，重要事项请点开原话再确认。
            </p>
          </section>

          <section className="rail-section">
            <div className="section-heading section-heading--tight">
              <h2>需要你处理</h2>
              <span className="section-count">{data.action_open}</span>
            </div>
            {data.actions.length ? (
              <div className="rail-actions">
                {[...data.actions]
                  .sort((a, b) => Number(a.done) - Number(b.done))
                  .map((action) => (
                    <ActionRow
                      key={action.id}
                      action={action}
                      onChanged={changeAction}
                    />
                  ))}
              </div>
            ) : (
              <p className="muted rail-clear">这段没有需要你处理的事。</p>
            )}
          </section>

          <section className="rail-section rail-section--file">
            <div className="section-heading section-heading--tight">
              <h2>文件</h2>
            </div>
            <dl className="file-facts">
              <div>
                <dt>文件名</dt>
                <dd title={data.name}>{data.name}</dd>
              </div>
              <div>
                <dt>录音时间</dt>
                <dd>{fullDate(data.recorded_at)}</dd>
              </div>
              <div>
                <dt>上传时间</dt>
                <dd>{formatDateTime(data.uploaded_at)}</dd>
              </div>
              <div>
                <dt>大小</dt>
                <dd>{formatBytes(data.size)}</dd>
              </div>
              <div>
                <dt>转写</dt>
                <dd>{data.transcript_source === "demo" ? "演示数据" : data.model || data.transcript_source || "未转写"}</dd>
              </div>
              <div>
                <dt>说话人</dt>
                <dd>
                  {Object.values(data.speakers || {}).join(" / ") || "未设置"}
                  {data.speaker_mode === "manual" ? <span className="rail-source"> 已手动命名</span> : null}
                </dd>
              </div>
            </dl>
            {data.is_demo ? <p className="rail-note">这是用于展示界面的演示录音，内容为虚构。</p> : null}
          </section>

          <div className="rail-signoff">
            <Headphones size={14} aria-hidden="true" />
            <span>听完再决定，不必急着处理。</span>
          </div>
        </aside>
      </div>
    </div>
  );
}
