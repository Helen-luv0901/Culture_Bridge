import { aiPanel } from "../data/ai";

function RecommendationBlock({ title, items }) {
  return (
    <div className="recommend-block">
      <h5>{title}</h5>
      <div className="pill-list">
        {items.map((item) => (
          <div key={item} className="pill">
            {item}
          </div>
        ))}
      </div>
    </div>
  );
}

export default function AiScreen() {
  return (
    <div className="ai-stack">
      <div className="prompt">{aiPanel.prompt}</div>
      <article className="card ai-panel">
        <div className="reply">
          <div className="ai-avatar">AI</div>
          <div>
            <strong>{aiPanel.title}</strong>
            <div className="subtle">{aiPanel.subtitle}</div>
          </div>
        </div>
        <div className="ai-block">
          <h4>Answer</h4>
          <p>{aiPanel.summary}</p>
        </div>
        <div className="knowledge-proof">
          <div><span>Based on</span><strong>Culture Bridge Knowledge #WP001</strong></div>
          <div><span>Status</span><strong>Recently Verified</strong></div>
          <div><span>Last verified</span><strong>2026-08-16</strong></div>
          <div><span>Recent users</span><strong>17 successful completions</strong></div>
        </div>
        <div className="ai-actions"><button type="button">Start this Action</button><button type="button">View sources</button></div>
        <RecommendationBlock title="參考貼文" items={aiPanel.referencePosts} />
        <RecommendationBlock title="相關影片" items={aiPanel.referenceVideos} />
      </article>
    </div>
  );
}
