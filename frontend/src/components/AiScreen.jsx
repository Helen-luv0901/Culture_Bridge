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
          <h4>答案摘要</h4>
          <p>{aiPanel.summary}</p>
        </div>
        <RecommendationBlock title="參考貼文" items={aiPanel.referencePosts} />
        <RecommendationBlock title="相關影片" items={aiPanel.referenceVideos} />
      </article>
    </div>
  );
}
