import { useEffect, useState } from "react";
import {
  ArrowRight,
  CheckSquare,
  Link as LinkIcon,
  PhoneCall,
  Plus,
  UploadSimple,
} from "@phosphor-icons/react";
import { Link } from "react-router-dom";
import { usePlayer } from "../contexts";
import { useApi, useRefreshEvent } from "../lib/hooks";
import type { ActionItem, Overview } from "../types";
import {
  cx,
  formatDateTime,
  formatDuration,
  formatDurationLong,
  formatMonthDay,
  progressFor,
  weekdayName,
} from "../lib/format";
import {
  Avatar,
  EmptyState,
  PageHead,
  PlayButton,
  SkeletonRows,
  StatusPill,
  Tag,
  UploadButton,
} from "../components/ui";
import { RecordingRows } from "../components/RecordingRow";
import { Waveform } from "../components/Waveform";
import { ActionRow } from "../components/ActionRow";

export function OverviewPage() {
  const { data, loading, error, reload } = useApi<Overview>("/api/overview", {
    pollMs: 8000,
  });
  const player = usePlayer();
  const [actions, setActions] = useState<ActionItem[]>([]);

  useEffect(() => {
    document.title = "总览 · 声册";
  }, []);
  useRefreshEvent(reload);
  useEffect(() => {
    if (data) setActions(data.actions);
  }, [data]);

  const handleActionChanged = (action: ActionItem, done: boolean) => {
    setActions((current) => {
      if (done) return current.filter((item) => item.id !== action.id);
      if (current.some((item) => item.id === action.id)) return current;
      return [action, ...current];
    });
  };

  if (loading && !data) {
    return (
      <div className="page">
        <PageHead title="今天" description="正在打开今天的档案。" />
        <div className="overview-grid">
          <div className="deck deck--skeleton" />
          <div className="skeleton-panel">
            <SkeletonRows count={3} />
          </div>
        </div>
      </div>
    );
  }

  if (error && !data) {
    return (
      <div className="page">
        <PageHead title="今天" description="没能读到档案。" />
        <EmptyState
          title="服务器暂时没有回应"
          action={
            <button type="button" className="btn btn--primary" onClick={reload}>
              再试一次
            </button>
          }
        >
          <p>{error}</p>
        </EmptyState>
      </div>
    );
  }

  if (!data) return null;
  const latest = data.latest;
  const trackActive = latest ? player.isCurrent(latest.id) : false;
  const progress = trackActive
    ? progressFor(player.time, player.duration || latest?.duration || 0)
    : 0;
  const topContact = data.stats.top_contacts[0];
  const now = new Date();

  if (!latest && data.total_recordings === 0) {
    return (
      <div className="page">
        <PageHead
          title="今天"
          description={
            <span className="page-head__meta">
              <span>{formatMonthDay(now)} {weekdayName(now)}</span>
              <span>还没有录音</span>
            </span>
          }
          actions={<UploadButton label="先上传一段" />}
        />
        <div className="overview-empty">
          <div className="deck deck--empty">
            <span className="deck__mark" aria-hidden="true">
              <i />
              <i />
              <i />
              <i />
              <i />
              <i />
              <i />
            </span>
            <h2>把手机指向这台服务器，录音会自己进来。</h2>
            <p>
              在手机「录音监控」里填入 WebDAV 地址和账号，测试通过后开始监控。这里会按联系人、对话和待办把录音收好。
            </p>
            <div className="deck__actions">
              <Link to="/setup" className="btn btn--amber">
                <LinkIcon size={16} aria-hidden="true" />
                查看接入步骤
              </Link>
              <span className="deck__hint">也可以先手动上传一段试试。</span>
            </div>
          </div>
          <aside className="attention attention--empty">
            <div className="section-heading">
              <h2>需要你处理</h2>
            </div>
            <p className="attention__empty-text">待办会从录音摘要里整理出来，出现在这里。</p>
          </aside>
        </div>
        <section className="section">
          <div className="section-heading">
            <h2>最近的录音</h2>
          </div>
          <EmptyState
            compact
            icon={<UploadSimple size={22} />}
            title="还没有可以回听的录音"
            action={<UploadButton label="上传一段录音" />}
          >
            <p>支持 m4a、mp3、wav、caf 等常见音频，也接受文档和图片。</p>
          </EmptyState>
        </section>
      </div>
    );
  }

  return (
    <div className="page">
      <PageHead
        title="今天"
        description={
          <span className="page-head__meta">
            <span>{formatMonthDay(now)} {weekdayName(now)}</span>
            <span>{data.today_count ? `今天收录 ${data.today_count} 段` : "今天还没有新录音"}</span>
            {data.processing > 0 ? <span className="text-amber">正在整理 {data.processing} 个文件</span> : null}
          </span>
        }
        actions={
          <>
            <Link to="/setup" className="btn btn--ghost btn--small">
              接入手机
            </Link>
            <UploadButton />
          </>
        }
      />

      <div className="overview-grid">
        <section className={cx("deck", !latest && "deck--empty")} aria-label="最新录音">
          {latest ? (
            <>
              <div className="deck__top">
                <div className="deck__who">
                  <Avatar contact={latest.contact} name={latest.contact?.name || "我"} size="sm" />
                  <span>{latest.contact?.name || latest.kind_label}</span>
                  {latest.contact ? <span className="deck__kind">{latest.kind_label}</span> : null}
                </div>
                <span className="deck__when mono">{formatDateTime(latest.recorded_at)}</span>
              </div>

              <div className="deck__main">
                <div className="deck__text">
                  <h2>{latest.title}</h2>
                  {latest.summary ? <p className="deck__summary">{latest.summary}</p> : null}
                  <div className="deck__tags">
                    {latest.topics.slice(0, 2).map((topic) => (
                      <Tag key={topic} tone="amber">{topic}</Tag>
                    ))}
                    {latest.action_open > 0 ? (
                      <span className="deck__todo">
                        <CheckSquare size={14} aria-hidden="true" />
                        {latest.action_open} 件待办
                      </span>
                    ) : null}
                  </div>
                </div>

                <div className="deck__player">
                  <div className="deck__playline">
                    <PlayButton recording={latest} size="xl" />
                    <div>
                      <div className="deck__time mono">{formatDuration(trackActive ? player.time : 0)}</div>
                      <div className="deck__duration mono">{formatDuration(latest.duration)}</div>
                    </div>
                  </div>
                  <Waveform
                    peaks={latest.waveform}
                    progress={progress}
                    currentTime={trackActive ? player.time : 0}
                    duration={latest.duration || 0}
                    onSeek={(time) => {
                      if (!trackActive) {
                        player.play(
                          {
                            id: latest.id,
                            title: latest.title,
                            kind: latest.kind,
                            src: latest.audio_url || `/api/recordings/${latest.id}/audio`,
                            duration: latest.duration,
                            contact: latest.contact,
                            waveform: latest.waveform || [],
                          },
                          time
                        );
                      } else {
                        player.seek(time);
                      }
                    }}
                    bars={110}
                    height={82}
                    dark
                  />
                </div>
              </div>

              <div className="deck__foot">
                <div className="deck__quote">
                  {latest.segments.length ? (
                    <>
                      <span className="deck__quote-speaker">
                        {latest.speakers[latest.segments[latest.segments.length - 1].speaker] ||
                          latest.segments[latest.segments.length - 1].speaker_name}
                      </span>
                      <span>“{latest.segments[latest.segments.length - 1].text}”</span>
                    </>
                  ) : (
                    <span>这段录音还在整理对话。</span>
                  )}
                </div>
                <Link to={`/recordings/${latest.id}`} className="deck__open">
                  打开完整对话
                  <ArrowRight size={16} aria-hidden="true" />
                </Link>
              </div>
            </>
          ) : (
            <>
              <h2>音频还在路上</h2>
              <p>已经有文件进来，等第一段录音处理完，这里就会变成播放台。</p>
              <Link to="/library" className="btn btn--amber">去文件库看看</Link>
            </>
          )}
        </section>

        <aside className="attention">
          <div className="section-heading section-heading--tight">
            <h2>需要你处理</h2>
            <Link to="/actions" className="section-heading__link">
              全部 {data.open_actions_total}
              <ArrowRight size={14} aria-hidden="true" />
            </Link>
          </div>
          {actions.length ? (
            <div className="attention__list">
              {actions.map((action) => (
                <ActionRow
                  key={action.id}
                  action={action}
                  onChanged={handleActionChanged}
                  compact
                />
              ))}
            </div>
          ) : (
            <div className="attention__clear">
              <CheckSquare size={22} aria-hidden="true" />
              <p>暂时没有需要你处理的事。</p>
              <span>摘要里出现明确的请求或承诺时，会出现在这里。</span>
            </div>
          )}
          <div className="attention__foot">
            <span className="dot dot--green" aria-hidden="true" />
            <span>已同步 {formatDateTime(new Date().toISOString())}</span>
          </div>
        </aside>
      </div>

      <section className="stats-strip" aria-label="最近七天通话">
        <div className="stats-strip__label">
          <PhoneCall size={17} aria-hidden="true" />
          最近 30 天
        </div>
        <div className="stats-strip__items">
          <span><strong className="mono">{data.stats.total_calls}</strong> 通电话</span>
          <span><strong className="mono">{formatDurationLong(data.stats.total_duration)}</strong> 通话时长</span>
          <span>
            {topContact ? (
              <>
                最常联系 <strong>{topContact.contact.name}</strong>
                <span className="muted"> {topContact.calls} 次</span>
              </>
            ) : (
              "还没有通话记录"
            )}
          </span>
        </div>
        <Link to="/calls" className="stats-strip__link">
          看通话统计
          <ArrowRight size={14} aria-hidden="true" />
        </Link>
      </section>

      <section className="section">
        <div className="section-heading">
          <h2>最近的录音</h2>
          <Link to="/recordings" className="section-heading__link">
            全部录音
            <ArrowRight size={14} aria-hidden="true" />
          </Link>
        </div>
        {data.recent.length ? (
          <RecordingRows items={data.recent} showDay />
        ) : (
          <EmptyState
            compact
            icon={<Plus size={22} />}
            title="还没有录音"
            action={<UploadButton label="上传一段" />}
          />
        )}
      </section>

      <p className="page-footnote">
        自动整理可能有误，重要事项请以原话为准。
        {data.processing > 0 ? <StatusPill status="processing" label="处理中" stageLabel="正在整理" /> : null}
      </p>
    </div>
  );
}
