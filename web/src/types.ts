export type Kind = "call" | "voice" | "audio" | "document" | "image" | "video" | "archive" | "other";
export type Status = "queued" | "processing" | "ready" | "failed";

export interface Contact {
  id: string;
  name: string;
  phone: string | null;
  initials: string;
  color: string;
}

export interface RecordingSummary {
  id: string;
  name: string;
  rel_path: string;
  kind: Kind;
  kind_label: string;
  category: string;
  status: Status;
  status_label: string;
  stage: string;
  stage_label: string;
  error: string | null;
  title: string;
  summary: string | null;
  excerpt: string;
  duration: number | null;
  duration_label: string;
  size: number;
  size_label: string;
  recorded_at: string;
  uploaded_at: string;
  processed_at: string | null;
  contact: Contact | null;
  topics: string[];
  tags: string[];
  action_open: number;
  action_total: number;
  has_audio: boolean;
  audio_url: string | null;
  is_demo: boolean;
  play_count: number;
  model: string;
  waveform?: number[];
}

export interface Segment {
  id: string;
  idx: number;
  start: number;
  end: number;
  speaker: string;
  speaker_name: string;
  text: string;
}

export interface ActionItem {
  id: string;
  text: string;
  detail: string | null;
  due_date: string | null;
  due_label: string | null;
  priority: "high" | "normal" | "low" | string;
  done: boolean;
  segment_idx: number | null;
  segment_start: number | null;
  source: string;
  created_at: string;
  recording?: {
    id: string;
    title: string;
    name: string;
    kind: Kind;
    kind_label: string;
    recorded_at: string;
    contact: Contact | null;
  };
}

export interface RecordingDetail extends RecordingSummary {
  key_points: string[];
  speakers: Record<string, string>;
  speaker_mode: string;
  transcript_source: string;
  analysis_source: string;
  language: string;
  sha256: string | null;
  waveform: number[];
  segments: Segment[];
  actions: ActionItem[];
}

export interface StatsContact {
  contact: Contact;
  calls: number;
  duration: number;
  open_actions: number;
  last_at: string | null;
  last_call_id: string | null;
  last_title: string | null;
}

export interface Stats {
  range_days: number;
  start_date: string;
  end_date: string;
  total_calls: number;
  total_duration: number;
  unique_contacts: number;
  avg_duration: number;
  open_actions: number;
  top_contacts: StatsContact[];
  daily: { date: string; label: string; weekday: string; calls: number; duration: number }[];
  hours: { hour: number; calls: number }[];
  peak_hour: number | null;
  peak_weekday: string | null;
  recent: RecordingSummary[];
}

export interface Overview {
  latest: RecordingDetail | null;
  recent: RecordingSummary[];
  actions: ActionItem[];
  stats: Stats;
  open_actions_total: number;
  processing: number;
  failed: number;
  total_files: number;
  total_recordings: number;
  today_count: number;
}

export interface Badges {
  open_actions: number;
  processing: number;
  failed: number;
  total_files: number;
  latest_upload_at: string | null;
}

export interface Paged<T> {
  items: T[];
  total: number;
  page: number;
  page_size: number;
  pages: number;
}

export interface FilesResponse extends Paged<RecordingSummary> {
  categories: { name: string; count: number }[];
  kind_counts: Record<string, number>;
}

export interface ContactsResponse {
  items: {
    contact: Contact;
    calls: number;
    duration: number;
    last_at: string | null;
    open_actions: number;
  }[];
}

export interface SetupInfo {
  dav_url: string;
  dav_username: string;
  dav_password: string | null;
  dav_password_visible: boolean;
  base_url: string;
  https: boolean;
  max_upload_mb: number;
  whisper_model: string;
  whisper_language: string;
  llm_enabled: boolean;
  llm_model: string | null;
  asr_engine: string;
  demo_mode: boolean;
  data_dir: string;
  library_dir: string;
  total_files: number;
  total_size: number;
  queued: number;
  failed: number;
  version: string;
}

export interface SystemGpu {
  index: number;
  name: string;
  memory_total_mb: number;
  memory_used_mb: number;
  utilization_percent: number;
  temperature_c: number;
  driver_version: string;
}

export interface SystemInfo {
  asr: {
    device: "cpu" | "cuda";
    device_index: number;
    model: string;
    compute_type: string;
    threads: number;
    gpu_supported: boolean;
    gpu_image: boolean;
  };
  gpus: SystemGpu[];
  gpu_error: string | null;
  cuda_device_count: number;
  intel_note: string;
  resources: {
    cpu_percent: number;
    cpu_cores_used: number;
    cpu_limit: number;
    memory_used: number;
    memory_limit: number;
    memory_percent: number;
    host_memory_total: number;
    host_memory_available: number;
    host_memory_used: number;
    load_1: number;
    load_5: number;
    load_15: number;
  };
  queue: {
    queued: number;
    processing: number;
    failed: number;
    current: { id: string; title: string; name: string; stage: string } | null;
  };
  worker: {
    paused: boolean;
    guard_paused: boolean;
    temperature: number | null;
    enabled: boolean;
  };
  thermal: {
    enabled: boolean;
    pause_c: number;
    resume_c: number;
    temperature_c: number | null;
  };
  timestamp: string;
}

export interface AIConfig {
  provider: string;
  base_url: string;
  model: string;
  has_key: boolean;
  key_hint: string;
}

export interface AIRule {
  id: string;
  match: string;
  kind: string | null;
  category: string | null;
  title: string | null;
  contact: string | null;
  enabled: boolean;
  source: string;
}
