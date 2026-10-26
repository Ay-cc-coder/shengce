import { useEffect, useMemo, useState } from "react";
import { CheckSquare, ClockCounterClockwise, Flag } from "@phosphor-icons/react";
import { Link } from "react-router-dom";
import { useApi, useRefreshEvent } from "../lib/hooks";
import type { ActionItem } from "../types";
import { useToast } from "../contexts";
import { actionBucket, cx } from "../lib/format";
import { EmptyState, PageHead, SkeletonRows } from "../components/ui";
import { ActionRow } from "../components/ActionRow";

type Filter = "open" | "done" | "all";

const BUCKET_LABELS: Record<string, string> = {
  overdue: "已逾期",
  today: "今天",
  week: "接下来 7 天",
  later: "更晚",
  none: "未设日期",
};

interface ActionResponse {
  items: ActionItem[];
  open_count: number;
  done_count: number;
  total: number;
}

export function ActionsPage() {
  const [filter, setFilter] = useState<Filter>("open");
  const { data, loading, error, reload } = useApi<ActionResponse>("/api/actions?status=all", {
    pollMs: 30000,
  });
  const [items, setItems] = useState<ActionItem[]>([]);
  const toast = useToast();
  useRefreshEvent(reload);

  useEffect(() => {
    document.title = "待办 · 声册";
  }, []);
  useEffect(() => {
    if (data) setItems(data.items);
  }, [data]);

  const openItems = useMemo(() => items.filter((item) => !item.done), [items]);
  const doneItems = useMemo(() => items.filter((item) => item.done), [items]);

  const groups = useMemo(() => {
    if (filter === "done") {
      return [{ key: "done", label: "已完成", items: doneItems }];
    }
    const order = ["overdue", "today", "week", "later", "none"];
    const openGroups = order
      .map((key) => ({
        key,
        label: BUCKET_LABELS[key],
        items: openItems.filter((item) => actionBucket(item.due_date) === key),
      }))
      .filter((group) => group.items.length > 0);
    if (filter === "open") return openGroups;
    return doneItems.length
      ? [...openGroups, { key: "done", label: "已完成", items: doneItems }]
      : openGroups;
  }, [filter, openItems, doneItems]);

  const changeAction = (action: ActionItem, done: boolean) => {
    setItems((current) =>
      current.map((item) =>
        item.id === action.id ? { ...item, done } : item
      )
    );
    if (done) toast.show("已标记完成。", "success");
  };

  const visible = filter === "done" ? doneItems : filter === "all" ? items : openItems;

  return (
    <div className="page">
      <PageHead
        title="待办"
        description={
          <span className="page-head__meta">
            <span>{openItems.length ? `${openItems.length} 件等你处理` : "手头是空的"}</span>
            {doneItems.length ? <span>已完成 {doneItems.length} 件</span> : null}
          </span>
        }
      />

      <div className="toolbar toolbar--actions">
        <div className="segmented" role="group" aria-label="待办筛选">
          {(
            [
              ["open", `待处理 ${openItems.length}`],
              ["done", `已完成 ${doneItems.length}`],
              ["all", "全部"],
            ] as const
          ).map(([value, label]) => (
            <button
              key={value}
              type="button"
              className={cx("segmented__item", filter === value && "is-active")}
              onClick={() => setFilter(value)}
              aria-pressed={filter === value}
            >
              {label}
            </button>
          ))}
        </div>
        <span className="toolbar__hint">在录音对话里手动添加待办，勾选完成不会删除原录音。</span>
      </div>

      {error ? (
        <EmptyState
          title="待办没有加载出来"
          action={<button type="button" className="btn btn--primary" onClick={reload}>再试一次</button>}
        >
          <p>{error}</p>
        </EmptyState>
      ) : null}

      {!error && loading && !data ? <SkeletonRows count={5} /> : null}

      {!error && !loading && visible.length === 0 ? (
        <EmptyState
          icon={<CheckSquare size={26} />}
          title={filter === "done" ? "还没有完成的待办" : "没有待处理的事"}
          action={
            filter !== "done" ? (
              <Link to="/recordings" className="btn btn--secondary">
                去听一段录音
              </Link>
            ) : null
          }
        >
          <p>
            {filter === "done"
              ? "完成的待办会留在这里，方便回看这段时间处理过什么。"
              : "在录音对话里点“+ 待办”，写给谁、做什么、什么时候完成，添加后会显示在这里。"}
          </p>
        </EmptyState>
      ) : null}

      <div className="action-groups">
        {groups.map((group) => (
          <section className="action-group" key={group.key}>
            <div className="action-group__head">
              {group.key === "overdue" ? <Flag size={15} aria-hidden="true" /> : null}
              {group.key === "done" ? <ClockCounterClockwise size={15} aria-hidden="true" /> : null}
              <h2>{group.label}</h2>
              <span className="mono">{group.items.length}</span>
            </div>
            <div className="action-group__list">
              {group.items.map((action) => (
                <ActionRow
                  key={action.id}
                  action={action}
                  onChanged={changeAction}
                  showQuote
                />
              ))}
            </div>
          </section>
        ))}
      </div>

      <p className="page-footnote">
        待办需要你从录音对话里手动添加；不会再把每段录音自动变成待办。
      </p>
    </div>
  );
}
