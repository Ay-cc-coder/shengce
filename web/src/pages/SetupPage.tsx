import { useEffect, useState } from "react";
import {
  Check,
  Copy,
  Eye,
  EyeSlash,
  HardDrive,
  LockKey,
  ShieldCheck,
  Warning,
} from "@phosphor-icons/react";
import { useApi } from "../lib/hooks";
import type { SetupInfo } from "../types";
import { useToast } from "../contexts";
import { cx, formatBytes } from "../lib/format";
import { EmptyState, PageHead, SkeletonRows, Tag } from "../components/ui";

interface Storage {
  total: number;
  used: number;
  free: number;
}

async function copyText(text: string): Promise<void> {
  if (navigator.clipboard) {
    try {
      await navigator.clipboard.writeText(text);
      return;
    } catch {
      // fall through to the old path
    }
  }
  const area = document.createElement("textarea");
  area.value = text;
  area.style.position = "fixed";
  area.style.opacity = "0";
  document.body.appendChild(area);
  area.select();
  document.execCommand("copy");
  area.remove();
}

export function SetupPage() {
  const { data, loading, error, reload } = useApi<SetupInfo>("/api/setup");
  const storage = useApi<Storage>("/api/setup/storage");
  const toast = useToast();
  const [reveal, setReveal] = useState(false);
  const [copied, setCopied] = useState<string | null>(null);

  useEffect(() => {
    document.title = "接入手机 · 声册";
  }, []);

  const copy = async (value: string, label: string) => {
    try {
      await copyText(value);
      setCopied(label);
      toast.show(`${label}已复制。`, "success");
      window.setTimeout(() => setCopied(null), 1800);
    } catch {
      toast.show("浏览器不允许复制，请手动选择。", "error");
    }
  };

  if (loading && !data) {
    return (
      <div className="page">
        <PageHead title="接入手机" description="正在读取服务器配置。" />
        <SkeletonRows count={4} />
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="page">
        <PageHead title="接入手机" />
        <EmptyState
          title="配置没有加载出来"
          action={<button type="button" className="btn btn--primary" onClick={reload}>再试一次</button>}
        >
          <p>{error}</p>
        </EmptyState>
      </div>
    );
  }

  const password = data.dav_password;

  return (
    <div className="page">
      <PageHead
        title="接入手机"
        description={
          <span className="page-head__meta">
            <span>让「录音监控」把手机里的录音送到这台服务器</span>
            <span>WebDAV</span>
          </span>
        }
        actions={
          <Tag tone={data.https ? "amber" : "muted"}>
            {data.https ? "HTTPS 已启用" : "当前是 HTTP"}
          </Tag>
        }
      />

      {!data.https ? (
        <div className="notice notice--warning">
          <Warning size={20} aria-hidden="true" />
          <div>
            <strong>手机插件只接受 HTTPS。</strong>
            <p>
              用域名和反向代理（例如 Caddy）启用 HTTPS 后，再在手机上测试连接。当前页面可以通过局域网
              HTTP 打开，但手机的 WebDAV 测试会失败。
            </p>
          </div>
        </div>
      ) : null}

      <div className="setup-layout">
        <section className="setup-main">
          <div className="section-heading">
            <h2>在手机上填入</h2>
            <span className="section-count">3 步</span>
          </div>

          <div className="setup-panel">
            <div className="setup-field">
              <div className="setup-field__head">
                <span>WebDAV 地址</span>
                <span className="setup-field__hint">以 /dav/ 结尾</span>
              </div>
              <div className="setup-field__value">
                <code>{data.dav_url}</code>
                <button
                  type="button"
                  className="icon-btn"
                  onClick={() => void copy(data.dav_url, "地址")}
                  aria-label="复制 WebDAV 地址"
                >
                  {copied === "地址" ? <Check size={16} /> : <Copy size={16} />}
                </button>
              </div>
            </div>

            <div className="setup-field">
              <div className="setup-field__head">
                <span>账号</span>
              </div>
              <div className="setup-field__value">
                <code>{data.dav_username}</code>
                <button
                  type="button"
                  className="icon-btn"
                  onClick={() => void copy(data.dav_username, "账号")}
                  aria-label="复制账号"
                >
                  {copied === "账号" ? <Check size={16} /> : <Copy size={16} />}
                </button>
              </div>
            </div>

            <div className="setup-field">
              <div className="setup-field__head">
                <span>密码</span>
                {data.dav_password_visible ? null : <span className="setup-field__hint">已隐藏</span>}
              </div>
              <div className="setup-field__value">
                <code>{password ? (reveal ? password : "••••••••••") : "请查看 .env 中的 DAV_PASSWORD"}</code>
                {password ? (
                  <>
                    <button
                      type="button"
                      className="icon-btn"
                      onClick={() => setReveal((value) => !value)}
                      aria-label={reveal ? "隐藏密码" : "显示密码"}
                    >
                      {reveal ? <EyeSlash size={16} /> : <Eye size={16} />}
                    </button>
                    <button
                      type="button"
                      className="icon-btn"
                      onClick={() => void copy(password, "密码")}
                      aria-label="复制密码"
                    >
                      {copied === "密码" ? <Check size={16} /> : <Copy size={16} />}
                    </button>
                  </>
                ) : null}
              </div>
            </div>
          </div>

          <ol className="setup-steps">
            <li>
              <span className="setup-steps__num mono">1</span>
              <div>
                <strong>打开手机上的「录音监控」</strong>
                <p>选择要监控的录音文件夹，比如通话录音或语音备忘录。</p>
              </div>
            </li>
            <li>
              <span className="setup-steps__num mono">2</span>
              <div>
                <strong>填写上面的地址、账号和密码</strong>
                <p>地址必须是 HTTPS。测试会检查地址、账号和写入权限。</p>
              </div>
            </li>
            <li>
              <span className="setup-steps__num mono">3</span>
              <div>
                <strong>测试通过后开始监控</strong>
                <p>已有文件会先上传，之后的新文件会自动出现。测试探针文件不会进入资料库。</p>
              </div>
            </li>
          </ol>

          <div className="setup-checks">
            <h3>连不上时先看这里</h3>
            <ul>
              <li><Check size={14} aria-hidden="true" /> 手机和服务器在同一个网络，或域名可以从外网访问。</li>
              <li><Check size={14} aria-hidden="true" /> 反向代理把 <code>/dav/</code> 原样转发，不剥离路径。</li>
              <li><Check size={14} aria-hidden="true" /> 证书受 iOS 信任；插件不支持自签名证书绕过。</li>
              <li><Check size={14} aria-hidden="true" /> 容器可以写入 <code>data/</code> 目录。</li>
            </ul>
          </div>
        </section>

        <aside className="setup-rail">
          <section className="rail-section">
            <div className="section-heading section-heading--tight">
              <h2>这台服务器</h2>
            </div>
            <dl className="file-facts">
              <div>
                <dt>版本</dt>
                <dd className="mono">{data.version}</dd>
              </div>
              <div>
                <dt>语音模型</dt>
                <dd>{data.asr_engine === "fake" ? "测试夹具" : data.whisper_model}</dd>
              </div>
              <div>
                <dt>转写语言</dt>
                <dd>{data.whisper_language === "zh" ? "中文" : data.whisper_language}</dd>
              </div>
              <div>
                <dt>摘要方式</dt>
                <dd>{data.llm_enabled ? data.llm_model : "本机规则"}</dd>
              </div>
              <div>
                <dt>单文件上限</dt>
                <dd>{data.max_upload_mb} MB</dd>
              </div>
              <div>
                <dt>资料目录</dt>
                <dd className="truncate" title={data.library_dir}>{data.library_dir}</dd>
              </div>
            </dl>
            {storage.data ? (
              <div className="storage">
                <div className="storage__head">
                  <span><HardDrive size={15} aria-hidden="true" /> 磁盘</span>
                  <span className="mono">{formatBytes(storage.data.free)} 可用</span>
                </div>
                <div className="storage__bar" aria-hidden="true">
                  <span
                    style={{
                      width: `${Math.min(100, Math.max(2, (storage.data.used / Math.max(1, storage.data.total)) * 100))}%`,
                    }}
                  />
                </div>
              </div>
            ) : null}
          </section>

          <section className="rail-section">
            <div className="section-heading section-heading--tight">
              <h2>隐私</h2>
            </div>
            <div className="privacy-list">
              <p><ShieldCheck size={16} aria-hidden="true" /> 音频只保存在本地 <code>data/library</code>。</p>
              <p><LockKey size={16} aria-hidden="true" /> 管理页和 WebDAV 使用两套密码。</p>
              <p>
                {data.llm_enabled
                  ? "摘要会调用你配置的模型服务，只发送当前录音的转写文本。"
                  : "没有配置模型服务，摘要由本机规则生成；待办需要你在录音对话里手动添加。"}
              </p>
            </div>
          </section>

          <section className="rail-section">
            <div className="section-heading section-heading--tight">
              <h2>当前资料库</h2>
            </div>
            <div className="setup-counts">
              <div><strong className="mono">{data.total_files}</strong><span>个文件</span></div>
              <div><strong className="mono">{data.queued}</strong><span>个在排队</span></div>
              <div><strong className={cx("mono", data.failed > 0 && "text-alert")}>{data.failed}</strong><span>个失败</span></div>
            </div>
            {data.demo_mode ? <p className="rail-note">当前是演示模式，资料库预置了虚构录音。</p> : null}
          </section>
        </aside>
      </div>
    </div>
  );
}
