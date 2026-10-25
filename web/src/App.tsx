import { useEffect, type ReactNode } from "react";
import { Navigate, Outlet, Route, Routes, useLocation } from "react-router-dom";
import { Sidebar } from "./components/Sidebar";
import { PlayerBar } from "./components/PlayerBar";
import { useAuth, usePlayer } from "./contexts";
import { cx } from "./lib/format";
import { LoginPage } from "./pages/LoginPage";
import { OverviewPage } from "./pages/OverviewPage";
import { RecordingsPage } from "./pages/RecordingsPage";
import { RecordingPage } from "./pages/RecordingPage";
import { CallsPage } from "./pages/CallsPage";
import { ActionsPage } from "./pages/ActionsPage";
import { FilesPage } from "./pages/FilesPage";
import { SetupPage } from "./pages/SetupPage";
import { NotFoundPage } from "./pages/NotFoundPage";

function ScrollToTop() {
  const { pathname } = useLocation();
  useEffect(() => {
    window.scrollTo({ top: 0, behavior: "auto" });
  }, [pathname]);
  return null;
}

function BootScreen() {
  return (
    <div className="boot">
      <div className="brand brand--large">
        <span className="brand__mark" aria-hidden="true">
          <i />
          <i />
          <i />
          <i />
          <i />
        </span>
        <span className="brand__text">
          <strong>声册</strong>
          <small>录音归档台</small>
        </span>
      </div>
      <div className="boot__line" />
      <p>正在打开档案</p>
    </div>
  );
}

function RequireAuth({ children }: { children: ReactNode }) {
  const auth = useAuth();
  const location = useLocation();
  if (auth.loading) return <BootScreen />;
  if (!auth.authenticated) {
    return <Navigate to="/login" replace state={{ from: location.pathname + location.search }} />;
  }
  return <>{children}</>;
}

function Shell() {
  const player = usePlayer();
  const location = useLocation();
  const barVisible = Boolean(
    player.track && location.pathname !== `/recordings/${player.track.id}`
  );
  return (
    <div className={cx("app-shell", barVisible && "has-player")}>
      <a href="#main" className="skip-link">
        跳到主要内容
      </a>
      <Sidebar />
      <main id="main" className="app-main">
        <Outlet />
      </main>
      <PlayerBar />
    </div>
  );
}

export function App() {
  return (
    <>
      <ScrollToTop />
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route
          element={
            <RequireAuth>
              <Shell />
            </RequireAuth>
          }
        >
          <Route index element={<OverviewPage />} />
          <Route path="recordings" element={<RecordingsPage />} />
          <Route path="recordings/:id" element={<RecordingPage />} />
          <Route path="calls" element={<CallsPage />} />
          <Route path="actions" element={<ActionsPage />} />
          <Route path="library" element={<FilesPage />} />
          <Route path="setup" element={<SetupPage />} />
          <Route path="*" element={<NotFoundPage />} />
        </Route>
      </Routes>
    </>
  );
}
