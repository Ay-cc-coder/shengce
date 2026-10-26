import {
  CheckSquare,
  FolderOpen,
  Gauge,
  GearSix,
  House,
  PhoneCall,
  SignOut,
  Waveform,
} from "@phosphor-icons/react";
import { NavLink, useNavigate } from "react-router-dom";
import { useAuth, useToast } from "../contexts";
import { useApi, useRefreshEvent } from "../lib/hooks";
import type { Badges } from "../types";
import { cx } from "../lib/format";

const NAV = [
  { to: "/", label: "总览", icon: House, end: true },
  { to: "/recordings", label: "录音", icon: Waveform, end: false },
  { to: "/calls", label: "通话", icon: PhoneCall, end: false },
  { to: "/actions", label: "待办", icon: CheckSquare, end: false },
  { to: "/library", label: "文件库", icon: FolderOpen, end: false },
];

function Brand() {
  return (
    <NavLink to="/" className="brand" aria-label="声册，回到总览">
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
    </NavLink>
  );
}

export function Sidebar() {
  const { data, reload } = useApi<Badges>("/api/badges", { pollMs: 60000 });
  const { logout, demoMode } = useAuth();
  const navigate = useNavigate();
  const toast = useToast();
  useRefreshEvent(reload);

  const handleLogout = async () => {
    await logout();
    toast.show("已退出登录。");
    navigate("/login", { replace: true });
  };

  const processing = data?.processing ?? 0;

  return (
    <>
      <div className="mobile-top">
        <Brand />
        <div className="mobile-top__actions">
          <NavLink to="/system" className="icon-btn" aria-label="运行状态">
            <Gauge size={19} />
          </NavLink>
          <NavLink to="/setup" className="icon-btn" aria-label="接入手机">
            <GearSix size={19} />
          </NavLink>
          <button type="button" className="icon-btn" onClick={() => void handleLogout()} aria-label="退出登录">
            <SignOut size={19} />
          </button>
        </div>
      </div>

      <aside className="sidebar">
        <div className="sidebar__head">
          <Brand />
        </div>

        <nav className="sidebar__nav" aria-label="主导航">
          {NAV.map((item) => {
            const Icon = item.icon;
            return (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.end}
                className={({ isActive }) => cx("nav-item", isActive && "is-active")}
              >
                {({ isActive }) => (
                  <>
                    <Icon size={19} weight={isActive ? "fill" : "regular"} aria-hidden="true" />
                    <span>{item.label}</span>
                    {item.to === "/actions" && (data?.open_actions ?? 0) > 0 ? (
                      <span className="nav-item__count mono">{data?.open_actions}</span>
                    ) : null}
                    {item.to === "/recordings" && processing > 0 ? (
                      <span className="nav-item__pulse" title={`${processing} 个文件处理中`} />
                    ) : null}
                  </>
                )}
              </NavLink>
            );
          })}
        </nav>

        <div className="sidebar__foot">
          <NavLink to="/system" className="sidebar__setup">
            <Gauge size={17} aria-hidden="true" />
            <span>运行状态</span>
          </NavLink>
          <NavLink to="/setup" className="sidebar__setup">
            <GearSix size={17} aria-hidden="true" />
            <span>接入手机</span>
          </NavLink>
          <div className="sidebar__status">
            <span className={cx("dot", processing > 0 ? "dot--amber" : "dot--green")} aria-hidden="true" />
            <span>{processing > 0 ? `正在整理 ${processing} 个文件` : "接收正常"}</span>
          </div>
          {demoMode ? <span className="sidebar__demo">演示数据</span> : null}
          <button type="button" className="sidebar__logout" onClick={() => void handleLogout()}>
            <SignOut size={16} aria-hidden="true" />
            退出登录
          </button>
        </div>
      </aside>
    </>
  );
}
