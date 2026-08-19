export default function TopicCard({ topic }) {
  return (
    <article className="card topic-card">
      <div className="topic-icon">{topic.icon}</div>
      <h4>{topic.title}</h4>
      <p>{topic.description}</p>
    </article>
  );
}
