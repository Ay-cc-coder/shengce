import { Link } from "react-router-dom";
import { Compass } from "@phosphor-icons/react";
import { EmptyState } from "../components/ui";

export function NotFoundPage() {
  return (
    <div className="page">
      <EmptyState
        icon={<Compass size={28} />}
        title="这一页不在档案里"
        action={
          <Link to="/" className="btn btn--primary">
            回到总览
          </Link>
        }
      >
        <p>地址可能写错了，或者这个页面已经搬走。</p>
      </EmptyState>
    </div>
  );
}
