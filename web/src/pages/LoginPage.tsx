import { useEffect, useState } from "react";
import { Eye, EyeSlash, LockKey } from "@phosphor-icons/react";
import { Navigate, useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "../contexts";

export function LoginPage() {
  const auth = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [password, setPassword] = useState("");
  const [reveal, setReveal] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const from = (location.state as { from?: string } | null)?.from || "/";

  useEffect(() => {
    document.title = "进入声册";
  }, []);

  if (auth.loading) {
    return (
      <div className="login-page login-page--loading">
        <div className="login-card login-card--quiet">
          <p className="muted">正在连接服务器</p>
        </div>
      </div>
    );
  }
  if (auth.authenticated) return <Navigate to={from} replace />;

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!password || submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      await auth.login(password);
      navigate(from, { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : "登录失败。");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="login-page">
      <section className="login-intro" aria-label="声册">
        <div className="login-intro__brand">
          <span className="brand__mark brand__mark--light" aria-hidden="true">
            <i />
            <i />
            <i />
            <i />
            <i />
          </span>
          <span>声册</span>
        </div>
        <div className="login-intro__text">
          <h1>把听过的，收好。</h1>
          <p>通话录音、语音备忘，收进这台服务器，再慢慢听。</p>
        </div>
        <div className="login-intro__signal" aria-hidden="true">
          {Array.from({ length: 48 }).map((_, index) => (
            <span
              key={index}
              style={{ height: `${18 + Math.abs(Math.sin(index * 0.52)) * 62}%` }}
            />
          ))}
        </div>
        <footer className="login-intro__foot">
          <span>私人录音归档</span>
          <span>本地部署</span>
        </footer>
      </section>

      <section className="login-form-wrap">
        <form className="login-form" onSubmit={submit}>
          <div className="login-form__head">
            <span className="login-form__icon" aria-hidden="true">
              <LockKey size={20} />
            </span>
            <div>
              <h2>进入声册</h2>
              <p>输入这台服务器的管理员密码。</p>
            </div>
          </div>

          <label className="field">
            <span className="field__label">密码</span>
            <span className="field__input-wrap">
              <input
                type={reveal ? "text" : "password"}
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                autoFocus
                autoComplete="current-password"
                placeholder="输入密码"
                aria-invalid={Boolean(error)}
                aria-describedby={error ? "login-error" : undefined}
              />
              <button
                type="button"
                className="field__reveal"
                onClick={() => setReveal((value) => !value)}
                aria-label={reveal ? "隐藏密码" : "显示密码"}
              >
                {reveal ? <EyeSlash size={17} /> : <Eye size={17} />}
              </button>
            </span>
          </label>

          {error || auth.error ? (
            <p className="form-error" id="login-error" role="alert">
              {error || auth.error}
            </p>
          ) : null}

          <button type="submit" className="btn btn--primary login-submit" disabled={submitting || !password}>
            {submitting ? "正在验证" : "进入"}
          </button>

          <p className="login-form__hint">
            首次启动时，密码会生成在服务器的 <code>data/admin-password.txt</code>；也可以在
            <code>.env</code> 里设置 <code>ADMIN_PASSWORD</code>。
          </p>
        </form>
        <p className="login-form__privacy">录音只保存在这台服务器上。默认不向外部服务发送音频。</p>
      </section>
    </div>
  );
}
