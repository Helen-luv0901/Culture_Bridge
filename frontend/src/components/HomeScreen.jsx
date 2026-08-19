import TopicCard from "./TopicCard";
import { topics } from "../data/topics";

export default function HomeScreen() {
  return (
    <>
      <div className="search">
        <span className="dot" />
        <span>搜尋生活問題、制度資訊、影片教學</span>
      </div>
      <div className="section-head">
        <h3>高頻主題</h3>
        <a href="#">查看全部</a>
      </div>
      <div className="topic-grid">
        {topics.map((topic) => (
          <TopicCard key={topic.title} topic={topic} />
        ))}
      </div>
    </>
  );
}
