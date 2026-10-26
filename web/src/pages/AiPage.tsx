import { useEffect, useState } from "react";
import {
  ArrowClockwise,
  CheckCircle,
  MagicWand,
  Sparkle,
  Trash,
  WarningCircle,
} from "@phosphor-icons/react";
import { api } from "../lib/api";
import { useApi } from "../lib/hooks";
import { useToast } from "../contexts";
import type { AIConfig, AIRule } from "../types";
import { cx } from "../lib/format";
import { EmptyState, PageHead, SkeletonRows, Tag } from "../components/ui";

const PROVIDERS = [
  { id: "deepseek", name: "DeepSeek", base_url: "https://api.deepseek.com/v1", model: "deepseek-chat" },
  { id: "openai", name: "OpenAI", base_url: "https://api.openai.com/v1", model: "gpt-4o-mini" },
  { id: "moonshot", name: "Moonshot", base_url: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k" },
  {
    id: "siliconflow",
    name: "SiliconFlow",
    base_url: "https://api.siliconflow.cn/v1",
    model: "Qwen/Qwen2.5-7B-Instruct",
  },
  {
    id: "dashscope",
    name: "阿里云百炼",
    base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1",
    model: "qwen-plus",
  },
  { id: "ollama", name: "本地 Ollama", base_url: "http://NAS_IP:11434/v1", model: "qwen2.5:7b" },
  { id: "custom", name: "自定义兼容接口", base_url: "", model: "" },
];

const KIND_LABELS: Record<string, string> = {
  call: "通话",
  voice: "语音备忘",
  audio: "音频",
  document: "文档",
  image: "图片",
  video: "视频",
  archive: "压缩包",
  other: "其他",
};

export function AiPage() {
  const configApi = useApi<AIConfig>("/api/ai/config");
  const rulesApi = useApi<{ items: AIRule[] }>("/api/ai/rules");
  const toast = useToast();
  const [provider, setProvider] = useState("deepseek");
  const [baseUrl, setBaseUrl] = useState("");
  const [apiKey, setApiKey] = useState("");
  const [model, setModel] = useState("");
  const [saving, setSaving] = useState(false);
  const [testing, setTesting] = useState(false);
  const [generating, setGenerating] = useState(false);
  const [applying, setApplying] = useState(false);
  const [fetchingModels, setFetchingModels] = useState(false);
  const [models, setModels] = useState<string[]>([]);
  const [manualModel, setManualModel] = useState(false);
  const [initialized, setInitialized] = useState(false);

  useEffect(() => {
    document.title = "AI 分类 · 声册";
  }, []);

  useEffect(() => {
    if (!configApi.data || initialized) return;
    setProvider(configApi.data.provider || "deepseek");
    setBaseUrl(configApi.data.base_url);
    setModel(configApi.data.model);
    setInitialized(true);
  }, [configApi.data, initialized]);

  const chooseProvider = (id: string) => {
    setProvider(id);
    const preset = PROVIDERS.find((item) => item.id === id);
    if (preset) {
      setBaseUrl(preset.base_url);
      setModel(preset.model);
    }
  };

  const saveConfig = async (): Promise<AIConfig | null> => {
    setSaving(true);
    try {
      const next = await api.put<AIConfig>("/api/ai/config", {
        provider,
        base_url: baseUrl,
        api_key: apiKey,
        model,
      });
      configApi.setData(next);
      setApiKey("");
      toast.show("AI 配置已保存。", "success");
      return next;
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "保存失败。", "error");
      return null;
    } finally {
      setSaving(false);
    }
  };

  const fetchModels = async () => {
    setFetchingModels(true);
    try {
      const saved = await saveConfig();
      if (!saved) return;
      const result = await api.get<{ models: string[] }>("/api/ai/models");
      setModels(result.models);
      setManualModel(false);
      if (result.models.length && !result.models.includes(model)) {
        setModel(result.models[0]);
      }
      toast.show(`获取到 ${result.models.length} 个模型。`, "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "获取模型失败。", "error");
    } finally {
      setFetchingModels(false);
    }
  };

  const test = async () => {
    setTesting(true);
    try {
      const saved = await saveConfig();
      if (!saved) return;
      const result = await api.post<{ ok: boolean; reply: string }>("/api/ai/test");
      toast.show(`连接成功：${result.reply}`, "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "连接失败。", "error");
    } finally {
      setTesting(false);
    }
  };

  const generate = async () => {
    setGenerating(true);
    try {
      await saveConfig();
      const result = await api.post<{ generated: number; sample_count: number }>("/api/ai/rules/generate");
      await rulesApi.reload();
      toast.show(`已从 ${result.sample_count} 个文件名生成 ${result.generated} 条规则。`, "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "生成规则失败。", "error");
    } finally {
      setGenerating(false);
    }
  };

  const applyRules = async () => {
    setApplying(true);
    try {
      const result = await api.post<{ changed: number }>("/api/ai/rules/apply");
      await rulesApi.reload();
      toast.show(`已更新 ${result.changed} 条现有录音的标题/分类。`, "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "应用规则失败。", "error");
    } finally {
      setApplying(false);
    }
  };

  const removeRule = async (rule: AIRule) => {
    try {
      await api.del(`/api/ai/rules/${rule.id}`);
      await rulesApi.reload();
      toast.show(`已删除规则「${rule.match}」。`, "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "删除失败。", "error");
    }
  };

  const config = configApi.data;
  const rules = rulesApi.data?.items || [];
  const currentPreset = PROVIDERS.find((item) => item.id === provider);

  return (
    <div className="page page--ai">
      <PageHead
        title="AI 分类"
        description="用大模型归纳文件名规则；以后新录音先查词表，不再每条都调用 AI。"
      />

      <div className="notice">
        <Sparkle size={20} aria-hidden="true" />
        <div>
          <strong>AI 只读取文件名，不发送录音音频或转写。</strong>
          <p>
            生成一次规则后，后续上传会先匹配词表；没有匹配到的新文件名仍按本地规则处理。
            保存的接口也会用于录音摘要。
          </p>
        </div>
      </div>

      <div className="ai-layout">
        <section className="section ai-config">
          <div className="section-heading">
            <h2>模型接口</h2>
            {config?.has_key ? <Tag tone="muted">已保存 Key {config.key_hint}</Tag> : null}
            <div className="section-heading__spacer" />
            <button type="button" className="btn btn--ghost btn--small" onClick={() => void test()} disabled={testing || saving}>
              <CheckCircle size={15} aria-hidden="true" />
              {testing ? "正在测试" : "保存并测试"}
            </button>
          </div>

          <div className="ai-form">
            <label className="field">
              <span className="field__label">服务商模板</span>
              <select value={provider} onChange={(event) => chooseProvider(event.target.value)}>
                {PROVIDERS.map((item) => (
                  <option key={item.id} value={item.id}>{item.name}</option>
                ))}
              </select>
            </label>

            <label className="field">
              <span className="field__label">服务器地址</span>
              <input
                value={baseUrl}
                onChange={(event) => setBaseUrl(event.target.value)}
                placeholder="https://api.deepseek.com/v1"
                spellCheck={false}
              />
            </label>

            <label className="field">
              <span className="field__label">API Key</span>
              <input
                type="password"
                value={apiKey}
                onChange={(event) => setApiKey(event.target.value)}
                placeholder={config?.has_key ? "已保存，留空保持不变" : "填写服务商提供的 Key"}
                autoComplete="off"
              />
            </label>

            <label className="field">
              <span className="field__label">模型名</span>
              <div className="field__row">
                {models.length && !manualModel ? (
                  <select value={model} onChange={(event) => setModel(event.target.value)}>
                    {models.map((item) => (
                      <option key={item} value={item}>{item}</option>
                    ))}
                  </select>
                ) : (
                  <input
                    value={model}
                    onChange={(event) => setModel(event.target.value)}
                    placeholder={currentPreset?.model || "deepseek-chat"}
                    spellCheck={false}
                  />
                )}
                <button
                  type="button"
                  className="btn btn--ghost btn--small"
                  onClick={() => void fetchModels()}
                  disabled={fetchingModels || saving}
                >
                  <ArrowClockwise size={15} aria-hidden="true" />
                  {fetchingModels ? "获取中" : "获取模型"}
                </button>
              </div>
              <div className="field__actions">
                {models.length ? (
                  <button type="button" className="link-btn" onClick={() => setManualModel((value) => !value)}>
                    {manualModel ? "从已获取列表选择" : "找不到？手动输入"}
                  </button>
                ) : null}
                <small className="field__hint">先点“获取模型”会自动列出服务商返回的全部模型；也可以手动填写。</small>
              </div>
            </label>
          </div>

          <p className="system-hint">
            本地 Ollama 要把 <code>NAS_IP</code> 换成 NAS 的局域网地址；容器里的 127.0.0.1 不是 NAS。
            保存后会立即用于摘要和规则生成。
          </p>

          <div className="ai-actions">
            <button type="button" className="btn btn--primary" onClick={() => void saveConfig()} disabled={saving || testing}>
              {saving ? "正在保存" : "保存配置"}
            </button>
            <button type="button" className="btn btn--ghost" onClick={() => void generate()} disabled={generating || saving}>
              <MagicWand size={16} aria-hidden="true" />
              {generating ? "AI 正在归纳" : "用 AI 生成规则"}
            </button>
          </div>

          {configApi.error ? (
            <div className="notice notice--warning">
              <WarningCircle size={18} aria-hidden="true" />
              <p>{configApi.error}</p>
            </div>
          ) : null}
        </section>

        <section className="section ai-rules">
          <div className="section-heading">
            <h2>词表规则</h2>
            <span className="section-count">{rules.length}</span>
            <div className="section-heading__spacer" />
            <button
              type="button"
              className="btn btn--ghost btn--small"
              onClick={() => void applyRules()}
              disabled={applying || !rules.length}
            >
              <ArrowClockwise size={15} aria-hidden="true" />
              {applying ? "正在应用" : "应用到现有录音"}
            </button>
          </div>

          {rulesApi.loading && !rulesApi.data ? (
            <SkeletonRows count={4} />
          ) : rules.length ? (
            <div className="rule-table">
              <div className="rule-table__head">
                <span>匹配文件名</span>
                <span>分类</span>
                <span>标题</span>
                <span />
              </div>
              {rules.map((rule) => (
                <div className="rule-row" key={rule.id}>
                  <span className="rule-row__match mono">{rule.match}</span>
                  <span>
                    <Tag tone="muted">{rule.category || KIND_LABELS[rule.kind || ""] || "未分类"}</Tag>
                  </span>
                  <span className={cx("rule-row__title", !rule.title && "muted")}>
                    {rule.title || "保留原规则"}
                  </span>
                  <button type="button" className="icon-btn" onClick={() => void removeRule(rule)} aria-label={`删除规则 ${rule.match}`}>
                    <Trash size={16} />
                  </button>
                </div>
              ))}
            </div>
          ) : (
            <EmptyState title="还没有规则">
              <p>先填写模型接口，然后点“用 AI 生成规则”。规则只包含文件名里的稳定前缀，不包含日期和随机 ID。</p>
            </EmptyState>
          )}

          <p className="system-hint">
            规则按“匹配文件名”做子串匹配；分类只改标题/类别，不会重写音频，也不会删除文件。
            应用规则后，已有录音的新标题会立即显示在列表里。
          </p>
        </section>
      </div>
    </div>
  );
}
