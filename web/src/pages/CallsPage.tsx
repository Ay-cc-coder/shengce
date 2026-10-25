import { useEffect, useMemo, useState } from "react";
import { ArrowRight, Clock, PhoneCall, UsersThree } from "@phosphor-icons/react";
import { Link } from "react-router-dom";
import { useApi, useRefreshEvent } from "../lib/hooks";
import type { Stats } from "../types";
import { cx, formatDuration, formatDurationLong, formatMonthDay, formatRelative } from "../lib/format";
import { Avatar, EmptyState, PageHead, SkeletonRows } from "../components/ui";
import { RecordingRows } from "../components/RecordingRow";

function DailyChart({ stats }: { stats: Stats }) {
  const max = Math.max(1, ...stats.daily.map((day) => day.calls));
  const total = stats.daily.reduce((sum, day) => sum + day.calls, 0);
  return (
    <div className="chart-block">
      <div className="chart-block__head">
        <div>
          <h2>通话量</h2>
          <p>每天接起的通话次数</p>
        </div>
        <span className="chart-block__summary mono">{total} 次</span>
      </div>
      <div
        className="daily-chart"
        role="img"
        aria-label={`${stats.range_days} 天内共 ${total} 次通话，单日最多 ${max} 次。`}
      >
        {stats.daily.map((day, index) => (
          <div className="daily-chart__slot" key={day.date}>
            <div
              className={cx("daily-chart__bar", day.calls === max && day.calls > 0 && "is-peak")}
              style={{ height: `${day.calls ? Math.max(8, (day.calls / max) * 100) : 2}%` }}
              title={`${formatMonthDay(day.date)} ${day.weekday} ${day.calls} 次`}
            />
            {index % Math.ceil(stats.daily.length / 6) === 0 ? (
              <span className="daily-chart__label">{day.label}</span>
            ) : null}
          </div>
        ))}
      </div>
      <p className="chart-block__foot">
        {stats.peak_weekday ? `${stats.peak_weekday}的通话最多。` : "还没有足够的通话数据。"}
      </p>
    </div>
  );
}

function HourChart({ stats }: { stats: Stats }) {
  const max = Math.max(1, ...stats.hours.map((hour) => hour.calls));
  return (
    <div className="chart-block chart-block--hours">
      <div className="chart-block__head">
        <div>
          <h2>来电时段</h2>
          <p>按录音开始时间统计</p>
        </div>
        {stats.peak_hour !== null ? (
          <span className="chart-block__summary mono">{stats.peak_hour}:00 最多</span>
        ) : null}
      </div>
      <div
        className="hour-chart"
        role="img"
        aria-label={
          stats.peak_hour !== null
            ? `通话最集中在 ${stats.peak_hour} 点。`
            : "还没有通话时段数据。"
        }
      >
        {stats.hours.map((hour) => (
          <div className="hour-chart__slot" key={hour.hour}>
            <div
              className={cx("hour-chart__bar", hour.hour === stats.peak_hour && hour.calls > 0 && "is-peak")}
              style={{ height: `${hour.calls ? Math.max(8, (hour.calls / max) * 100) : 2}%` }}
              title={`${hour.hour}:00 ${hour.calls} 次`}
            />
            {[0, 6, 12, 18, 23].includes(hour.hour) ? (
              <span className="hour-chart__label mono">{hour.hour}</span>
            ) : null}
          </div>
        ))}
      </div>
    </div>
  );
}

export function CallsPage() {
  const [days, setDays] = useState(30);
  const { data, loading, error, reload } = useApi<Stats>(`/api/stats?days=${days}`, {
    pollMs: 30000,
  });
  useRefreshEvent(reload);

  useEffect(() => {
    document.title = "通话 · 声册";
  }, []);

  const sentence = useMemo(() => {
    if (!data) return "";
    if (data.total_calls === 0) return `最近 ${data.range_days} 天还没有通话记录。`;
    if (data.unique_contacts === 0) return `最近 ${data.range_days} 天有 ${data.total_calls} 通电话。`;
    return `最近 ${data.range_days} 天，和 ${data.unique_contacts} 个人通了 ${data.total_calls} 次话。`;
  }, [data]);

  return (
    <div className="page">
      <PageHead
        title="通话"
        description={
          <span className="page-head__meta">
            <span>{sentence || "正在整理通话记录"}</span>
          </span>
        }
        actions={
          <div className="segmented segmented--small" role="group" aria-label="统计范围">
            {[7, 30, 90].map((value) => (
              <button
                key={value}
                type="button"
                className={cx("segmented__item", days === value && "is-active")}
                onClick={() => setDays(value)}
                aria-pressed={days === value}
              >
                {value} 天
              </button>
            ))}
          </div>
        }
      />

      {error ? (
        <EmptyState
          title="通话统计没有加载出来"
          action={<button type="button" className="btn btn--primary" onClick={reload}>再试一次</button>}
        >
          <p>{error}</p>
        </EmptyState>
      ) : null}

      {!error && loading && !data ? <SkeletonRows count={5} /> : null}

      {data && data.total_calls === 0 ? (
        <EmptyState
          icon={<PhoneCall size={26} />}
          title="这段时间没有通话"
          action={<Link to="/recordings" className="btn btn--secondary">去看全部录音</Link>}
        >
          <p>换成 90 天看看，或者等下一通电话被收进来。</p>
        </EmptyState>
      ) : null}

      {data && data.total_calls > 0 ? (
        <>
          <section className="calls-summary" aria-label="通话概况">
            <div className="calls-summary__item">
              <span className="calls-summary__value mono">{formatDurationLong(data.total_duration)}</span>
              <span className="calls-summary__label">总通话时长</span>
            </div>
            <div className="calls-summary__item">
              <span className="calls-summary__value mono">{formatDuration(data.avg_duration)}</span>
              <span className="calls-summary__label">平均每通</span>
            </div>
            <div className="calls-summary__item">
              <span className="calls-summary__value mono">{data.open_actions}</span>
              <span className="calls-summary__label">电话里留下的待办</span>
            </div>
            {data.peak_weekday ? (
              <div className="calls-summary__item">
                <span className="calls-summary__value">{data.peak_weekday}</span>
                <span className="calls-summary__label">通话最多的一天</span>
              </div>
            ) : null}
          </section>

          <div className="calls-grid">
            <section className="contact-rank" aria-label="常联系的人">
              <div className="section-heading">
                <h2>常联系的人</h2>
                <span className="section-count">{data.top_contacts.length} 位</span>
              </div>
              <div className="rank-list">
                {data.top_contacts.map((item, index) => {
                  const href = item.contact.id
                    ? `/recordings?contact=${item.contact.id}&contactName=${encodeURIComponent(item.contact.name)}`
                    : null;
                  const body = (
                    <>
                      <span className="rank-list__index mono">{String(index + 1).padStart(2, "0")}</span>
                      <Avatar contact={item.contact} size="md" />
                      <div className="rank-list__body">
                        <div className="rank-list__line">
                          <span className="rank-list__name">{item.contact.name}</span>
                          <span className="rank-list__count mono">{item.calls} 次</span>
                        </div>
                        <div className="rank-list__bar" aria-hidden="true">
                          <span
                            style={{
                              width: `${Math.max(8, (item.calls / Math.max(1, data.top_contacts[0].calls)) * 100)}%`,
                            }}
                          />
                        </div>
                        <div className="rank-list__meta">
                          <span>{formatDurationLong(item.duration)}</span>
                          {item.last_at ? <span>最近 {formatRelative(item.last_at)}</span> : null}
                          {item.open_actions > 0 ? <span className="text-alert">{item.open_actions} 件待办</span> : null}
                        </div>
                      </div>
                      {href ? <ArrowRight size={15} className="rank-list__arrow" aria-hidden="true" /> : null}
                    </>
                  );
                  return href ? (
                    <Link key={item.contact.id || item.contact.name} to={href} className="rank-list__row">
                      {body}
                    </Link>
                  ) : (
                    <div key={item.contact.name} className="rank-list__row rank-list__row--static">
                      {body}
                    </div>
                  );
                })}
              </div>
            </section>

            <HourChart stats={data} />
          </div>

          <DailyChart stats={data} />

          <section className="section">
            <div className="section-heading">
              <h2>最近的通话</h2>
              <Link to="/recordings?kind=call" className="section-heading__link">
                全部通话
                <ArrowRight size={14} aria-hidden="true" />
              </Link>
            </div>
            <RecordingRows items={data.recent} showDay />
          </section>

          <div className="calls-footnotes">
            <span><UsersThree size={15} aria-hidden="true" /> 联系人来自文件名与手动修改。</span>
            <span><Clock size={15} aria-hidden="true" /> 统计按录音开始时间，使用服务器时区。</span>
          </div>
        </>
      ) : null}
    </div>
  );
}
