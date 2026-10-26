import { useEffect, useRef, useState } from "react";
import {
  ArrowClockwise,
  CheckCircle,
  Cpu,
  GraphicsCard,
  HardDrive,
  ListBullets,
  Pause,
  Play,
  Thermometer,
  WarningCircle,
} from "@phosphor-icons/react";
import { api } from "../lib/api";
import { useApi } from "../lib/hooks";
import { useToast } from "../contexts";
import type { SystemInfo } from "../types";
import { cx, formatBytes } from "../lib/format";
import { EmptyState, PageHead, SkeletonRows, Tag } from "../components/ui";

const MODELS = ["base", "small", "medium", "large-v3", "large-v3-turbo"];

function Meter({
  label,
  value,
  max,
  display,
  tone = "amber",
}: {
  label: string;
  value: number;
  max: number;
  display: string;
  tone?: "amber" | "alert" | "signal";
}) {
  const percent = max > 0 ? Math.min(100, Math.max(0, (value / max) * 100)) : 0;
  return (
    <div className="meter">
      <div className="meter__head">
        <span>{label}</span>
        <span className="mono">{display}</span>
      </div>
      <div className="meter__track" aria-hidden="true">
        <span className={cx("meter__fill", `meter__fill--${tone}`)} style={{ width: `${percent}%` }} />
      </div>
    </div>
  );
}

export function SystemPage() {
  const { data, loading, error, reload, setData } = useApi<SystemInfo>("/api/system", {
    pollMs: 3000,
  });
  const toast = useToast();
  const [device, setDevice] = useState<"cpu" | "cuda">("cpu");
  const [gpuIndex, setGpuIndex] = useState(0);
  const [model, setModel] = useState("small");
  const [saving, setSaving] = useState(false);
  const [busy, setBusy] = useState(false);
  const initialized = useRef(false);

  useEffect(() => {
    document.title = "运行状态 · 声册";
  }, []);

  useEffect(() => {
    if (!data || initialized.current) return;
    setDevice(data.asr.device);
    setGpuIndex(data.asr.device_index);
    setModel(data.asr.model);
    initialized.current = true;
  }, [data]);

  const applyDevice = async () => {
    setSaving(true);
    try {
      const next = await api.post<SystemInfo>("/api/system/asr", {
        device,
        device_index: gpuIndex,
        model,
      });
      setData(next);
      toast.show("识别设备已更新，下一段录音会使用新设置。", "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "切换失败。", "error");
    } finally {
      setSaving(false);
    }
  };

  const toggleWorker = async () => {
    if (!data) return;
    setBusy(true);
    try {
      const next = await api.post<SystemInfo>("/api/system/worker", {
        paused: !data.worker.paused,
      });
      setData(next);
      toast.show(next.worker.paused ? "处理队列已暂停。" : "处理队列已继续。", "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "操作失败。", "error");
    } finally {
      setBusy(false);
    }
  };

  if (loading && !data) {
    return (
      <div className="page">
        <PageHead title="运行状态" description="正在读取容器资源和处理设备。" />
        <SkeletonRows count={4} />
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="page">
        <PageHead title="运行状态" />
        <EmptyState
          title="运行状态没有加载出来"
          action={<button type="button" className="btn btn--primary" onClick={reload}>再试一次</button>}
        >
          <p>{error}</p>
        </EmptyState>
      </div>
    );
  }

  const { asr, resources, queue, gpus, worker } = data;
  const currentGpu = gpus.find((gpu) => gpu.index === gpuIndex);
  const gpuAvailable = asr.gpu_supported && gpus.length > 0;
  const cpuPercent = Math.min(100, resources.cpu_percent);
  const memoryPercent = Math.min(100, resources.memory_percent);
  const hostPercent = resources.host_memory_total
    ? (resources.host_memory_used / resources.host_memory_total) * 100
    : 0;

  return (
    <div className="page page--system">
      <PageHead
        title="运行状态"
        description={
          <span className="page-head__meta">
            <span>实时刷新</span>
            <span>处理队列与 GPU</span>
          </span>
        }
        actions={
          <button type="button" className="btn btn--ghost btn--small" onClick={reload}>
            <ArrowClockwise size={16} aria-hidden="true" />
            刷新
          </button>
        }
      />

      {!asr.gpu_image ? (
        <div className="notice notice--warning">
          <WarningCircle size={20} aria-hidden="true" />
          <div>
            <strong>当前是 CPU 镜像，GPU 选项不可用。</strong>
            <p>
              如果 NAS 已经通过 Docker 透传 NVIDIA GPU，可以切换到 CUDA 镜像：
              在 compose 叠加 <code>docker-compose.gpu.yml</code>，并使用
              <code>ghcr.io/ay-cc-coder/shengce:cuda</code>。重启后这个页面会显示显卡并允许选择。
            </p>
          </div>
        </div>
      ) : null}

      {asr.gpu_image && !gpuAvailable ? (
        <div className="notice notice--warning">
          <WarningCircle size={20} aria-hidden="true" />
          <div>
            <strong>CUDA 镜像已加载，但容器没有可用的 NVIDIA GPU。</strong>
            <p>
              请在 compose 中确认 <code>gpus: all</code>，并确认容器内能执行
              <code>nvidia-smi</code>。{data.gpu_error}
            </p>
          </div>
        </div>
      ) : null}

      <div className="system-layout">
        <div className="system-main">
          <section className="section system-section">
            <div className="section-heading">
              <h2>识别设备</h2>
              <Tag tone={asr.device === "cuda" ? "amber" : "muted"}>
                {asr.device === "cuda" ? "GPU" : "CPU"}
              </Tag>
              <div className="section-heading__spacer" />
              <span className="section-count">{asr.model}</span>
            </div>

            <div className="device-picker">
              <button
                type="button"
                className={cx("device-option", device === "cpu" && "is-active")}
                onClick={() => setDevice("cpu")}
              >
                <Cpu size={22} aria-hidden="true" />
                <span>
                  <strong>CPU</strong>
                  <small>{asr.threads} 线程 · {asr.compute_type === "int8" ? "int8" : asr.compute_type}</small>
                </span>
                {device === "cpu" ? <CheckCircle size={18} weight="fill" aria-hidden="true" /> : null}
              </button>

              <button
                type="button"
                className={cx("device-option", device === "cuda" && "is-active")}
                onClick={() => gpuAvailable && setDevice("cuda")}
                disabled={!gpuAvailable}
                title={!gpuAvailable ? (asr.gpu_image ? data.gpu_error || "没有可用 GPU" : "当前是 CPU 镜像") : undefined}
              >
                <GraphicsCard size={22} aria-hidden="true" />
                <span>
                  <strong>NVIDIA GPU</strong>
                  <small>
                    {gpuAvailable
                      ? `${currentGpu?.name || gpus[0].name} · float16`
                      : asr.gpu_image
                        ? "容器内未发现可用 GPU"
                        : "需要 CUDA 镜像"}
                  </small>
                </span>
                {device === "cuda" ? <CheckCircle size={18} weight="fill" aria-hidden="true" /> : null}
              </button>
            </div>

            <div className="device-controls">
              {gpuAvailable && gpus.length > 1 ? (
                <label className="field">
                  <span className="field__label">显卡</span>
                  <select value={gpuIndex} onChange={(event) => setGpuIndex(Number(event.target.value))}>
                    {gpus.map((gpu) => (
                      <option key={gpu.index} value={gpu.index}>
                        {gpu.name} · {gpu.index}
                      </option>
                    ))}
                  </select>
                </label>
              ) : null}

              <label className="field">
                <span className="field__label">Whisper 模型</span>
                <select value={model} onChange={(event) => setModel(event.target.value)}>
                  {MODELS.map((item) => (
                    <option key={item} value={item}>
                      {item}
                    </option>
                  ))}
                </select>
              </label>

              <button type="button" className="btn btn--primary" onClick={() => void applyDevice()} disabled={saving}>
                {saving ? "正在应用" : "应用并重载模型"}
              </button>
            </div>
            <p className="system-hint">
              切换设备或模型后，正在处理的文件会继续用旧设置；从下一段录音开始使用新设置。GPU 模式使用 float16，CPU 模式使用 int8。
            </p>
          </section>

          <section className="section system-section">
            <div className="section-heading">
              <h2>容器资源</h2>
              <span className="section-count">实时</span>
              <div className="section-heading__spacer" />
              <Tag tone={worker.paused ? "muted" : "amber"}>
                {worker.paused ? "处理已暂停" : worker.enabled ? "正在处理" : "队列空闲"}
              </Tag>
              <button type="button" className="btn btn--ghost btn--small" onClick={() => void toggleWorker()} disabled={busy}>
                {worker.paused ? <Play size={15} aria-hidden="true" /> : <Pause size={15} aria-hidden="true" />}
                {worker.paused ? "继续转写" : "暂停转写"}
              </button>
            </div>

            <div className="meter-grid">
              <Meter
                label="CPU"
                value={cpuPercent}
                max={100}
                display={`${resources.cpu_percent.toFixed(1)}% · ${resources.cpu_cores_used.toFixed(2)} / ${resources.cpu_limit} 核`}
                tone={cpuPercent > 90 ? "alert" : "amber"}
              />
              <Meter
                label="容器内存"
                value={memoryPercent}
                max={100}
                display={`${formatBytes(resources.memory_used)} / ${formatBytes(resources.memory_limit)}`}
                tone={memoryPercent > 85 ? "alert" : "signal"}
              />
              <Meter
                label="NAS 内存"
                value={hostPercent}
                max={100}
                display={`${formatBytes(resources.host_memory_used)} / ${formatBytes(resources.host_memory_total)}`}
                tone={hostPercent > 85 ? "alert" : "signal"}
              />
              <div className="meter meter--static">
                <div className="meter__head">
                  <span>系统负载</span>
                  <span className="mono">
                    {resources.load_1} / {resources.load_5} / {resources.load_15}
                  </span>
                </div>
                <p>1 / 5 / 15 分钟平均负载</p>
              </div>
            </div>

            <div className="queue-strip">
              <div><strong className="mono">{queue.queued}</strong><span>排队</span></div>
              <div><strong className="mono">{queue.processing}</strong><span>处理中</span></div>
              <div><strong className={cx("mono", queue.failed > 0 && "text-alert")}>{queue.failed}</strong><span>失败</span></div>
              <div className="queue-strip__current">
                {queue.current ? (
                  <>
                    <span className="muted">当前：</span>
                    <strong>{queue.current.title}</strong>
                    <span className="muted">{queue.current.stage}</span>
                  </>
                ) : (
                  <span className="muted">队列没有正在处理的文件</span>
                )}
              </div>
            </div>
          </section>

          <section className="section system-section">
            <div className="section-heading">
              <h2>GPU</h2>
              <span className="section-count">{gpus.length}</span>
            </div>
            {gpus.length ? (
              <div className="gpu-list">
                {gpus.map((gpu) => (
                  <div key={gpu.index} className={cx("gpu-row", gpu.index === gpuIndex && "is-selected")}>
                    <GraphicsCard size={22} aria-hidden="true" />
                    <div className="gpu-row__body">
                      <div className="gpu-row__name">
                        <strong>{gpu.name}</strong>
                        <span className="mono">#{gpu.index}</span>
                      </div>
                      <div className="gpu-row__meta">
                        <span><HardDrive size={13} aria-hidden="true" /> {gpu.memory_used_mb} / {gpu.memory_total_mb} MB</span>
                        <span><Cpu size={13} aria-hidden="true" /> {gpu.utilization_percent}%</span>
                        <span><Thermometer size={13} aria-hidden="true" /> {gpu.temperature_c}°C</span>
                        <span className="muted">驱动 {gpu.driver_version}</span>
                      </div>
                      <div className="meter__track" aria-hidden="true">
                        <span
                          className="meter__fill meter__fill--amber"
                          style={{ width: `${Math.min(100, (gpu.memory_used_mb / Math.max(1, gpu.memory_total_mb)) * 100)}%` }}
                        />
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="gpu-empty">
                <GraphicsCard size={24} aria-hidden="true" />
                <p>{data.gpu_error || "没有检测到 NVIDIA GPU。"}</p>
                <span>{data.intel_note}</span>
              </div>
            )}
          </section>
        </div>

        <aside className="system-rail">
          <section className="rail-section">
            <div className="section-heading section-heading--tight">
              <h2>当前配置</h2>
            </div>
            <dl className="file-facts">
              <div><dt>设备</dt><dd>{asr.device === "cuda" ? currentGpu?.name || "NVIDIA GPU" : "CPU"}</dd></div>
              <div><dt>模型</dt><dd>{asr.model}</dd></div>
              <div><dt>精度</dt><dd>{asr.compute_type}</dd></div>
              <div><dt>CPU 线程</dt><dd>{asr.threads}</dd></div>
              <div><dt>队列</dt><dd>{queue.queued + queue.processing} 个待处理</dd></div>
            </dl>
          </section>

          <section className="rail-section">
            <div className="section-heading section-heading--tight">
              <h2>说明</h2>
            </div>
            <div className="privacy-list">
              <p><Cpu size={16} aria-hidden="true" /> GPU 模式下 CPU 只做预处理，仍建议保留内存上限。</p>
              <p><GraphicsCard size={16} aria-hidden="true" /> {data.intel_note}</p>
              <p><ListBullets size={16} aria-hidden="true" /> 暂停只会停止领取新文件，不会中断正在转写的那一段。</p>
            </div>
          </section>
        </aside>
      </div>
    </div>
  );
}
