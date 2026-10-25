export function cx(...values: Array<string | false | null | undefined>): string {
  return values.filter(Boolean).join(" ");
}

export function parseDate(value: string | null | undefined): Date | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function pad(value: number): string {
  return value.toString().padStart(2, "0");
}

export function formatTime(value: string | Date | null | undefined): string {
  const date = value instanceof Date ? value : parseDate(value ?? null);
  if (!date) return "";
  return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function formatDateTime(value: string | Date | null | undefined): string {
  const date = value instanceof Date ? value : parseDate(value ?? null);
  if (!date) return "";
  return `${date.getMonth() + 1}月${date.getDate()}日 ${formatTime(date)}`;
}

export function formatMonthDay(value: string | Date | null | undefined): string {
  const date = value instanceof Date ? value : parseDate(value ?? null);
  if (!date) return "";
  return `${date.getMonth() + 1}月${date.getDate()}日`;
}

export function weekdayName(value: string | Date | null | undefined): string {
  const date = value instanceof Date ? value : parseDate(value ?? null);
  if (!date) return "";
  return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][date.getDay()];
}

export function startOfDay(date: Date): Date {
  const copy = new Date(date);
  copy.setHours(0, 0, 0, 0);
  return copy;
}

export function sameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

export function dateKey(value: string | Date | null | undefined): string {
  const date = value instanceof Date ? value : parseDate(value ?? null);
  if (!date) return "";
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export function formatRelative(value: string | Date | null | undefined, now = new Date()): string {
  const date = value instanceof Date ? value : parseDate(value ?? null);
  if (!date) return "";
  if (sameDay(date, now)) return `今天 ${formatTime(date)}`;
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (sameDay(date, yesterday)) return `昨天 ${formatTime(date)}`;
  const days = Math.round((startOfDay(now).getTime() - startOfDay(date).getTime()) / 86400000);
  if (days > 0 && days < 7) return `${weekdayName(date)} ${formatTime(date)}`;
  if (date.getFullYear() === now.getFullYear()) {
    return `${formatMonthDay(date)} ${formatTime(date)}`;
  }
  return `${date.getFullYear()}年${formatMonthDay(date)} ${formatTime(date)}`;
}

export function formatDayHeading(value: string | Date | null | undefined, now = new Date()): string {
  const date = value instanceof Date ? value : parseDate(value ?? null);
  if (!date) return "";
  if (sameDay(date, now)) return "今天";
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (sameDay(date, yesterday)) return "昨天";
  if (date.getFullYear() === now.getFullYear()) {
    return `${formatMonthDay(date)} ${weekdayName(date)}`;
  }
  return `${date.getFullYear()}年${formatMonthDay(date)}`;
}

export function formatDuration(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined || Number.isNaN(seconds)) return "--:--";
  const total = Math.max(0, Math.round(seconds));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const secs = total % 60;
  if (hours > 0) return `${hours}:${pad(minutes)}:${pad(secs)}`;
  return `${minutes}:${pad(secs)}`;
}

export function formatDurationLong(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined) return "未知";
  const total = Math.max(0, Math.round(seconds));
  if (total < 60) return `${total} 秒`;
  const minutes = Math.floor(total / 60);
  const secs = total % 60;
  if (minutes < 60) return secs ? `${minutes} 分 ${secs} 秒` : `${minutes} 分钟`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest ? `${hours} 小时 ${rest} 分` : `${hours} 小时`;
}

export function formatBytes(value: number | null | undefined): string {
  if (!value) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let size = value;
  let index = 0;
  while (size >= 1024 && index < units.length - 1) {
    size /= 1024;
    index += 1;
  }
  return index === 0 ? `${Math.round(size)} B` : `${size.toFixed(1)} ${units[index]}`;
}

export function currentDateKey(now = new Date()): string {
  return dateKey(now);
}

export function dueStatus(
  dueDate: string | null,
  done = false
): { label: string; tone: "overdue" | "today" | "soon" | "later" | "none" } {
  if (!dueDate) return { label: "未设日期", tone: "none" };
  const date = new Date(`${dueDate}T00:00:00`);
  if (Number.isNaN(date.getTime())) return { label: "未设日期", tone: "none" };
  const today = startOfDay(new Date());
  const target = startOfDay(date);
  const diff = Math.round((target.getTime() - today.getTime()) / 86400000);
  if (done) return { label: formatMonthDay(date), tone: "none" };
  if (diff < 0) return { label: "已逾期", tone: "overdue" };
  if (diff === 0) return { label: "今天", tone: "today" };
  if (diff === 1) return { label: "明天", tone: "soon" };
  if (diff <= 7) return { label: `${weekdayName(date)}`, tone: "soon" };
  return { label: formatMonthDay(date), tone: "later" };
}

export function actionBucket(dueDate: string | null): "overdue" | "today" | "week" | "later" | "none" {
  if (!dueDate) return "none";
  const date = new Date(`${dueDate}T00:00:00`);
  if (Number.isNaN(date.getTime())) return "none";
  const diff = Math.round(
    (startOfDay(date).getTime() - startOfDay(new Date()).getTime()) / 86400000
  );
  if (diff < 0) return "overdue";
  if (diff === 0) return "today";
  if (diff <= 7) return "week";
  return "later";
}

export function progressFor(time: number, duration: number): number {
  if (!duration) return 0;
  return Math.min(1, Math.max(0, time / duration));
}

export function isToday(value: string | Date | null | undefined): boolean {
  const date = value instanceof Date ? value : parseDate(value ?? null);
  return date ? sameDay(date, new Date()) : false;
}

export function initials(name: string): string {
  const trimmed = name.trim();
  if (!trimmed) return "?";
  if (/^[\u4e00-\u9fff]/.test(trimmed)) {
    return trimmed.length > 2 ? trimmed.slice(-2) : trimmed;
  }
  const parts = trimmed.split(/\s+/).filter(Boolean);
  if (parts.length >= 2) return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  return trimmed.slice(0, 2).toUpperCase();
}
