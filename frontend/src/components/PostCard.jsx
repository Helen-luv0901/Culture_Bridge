export default function PostCard({ post }) {
  return (
    <article className="card post-card">
      <div className="post-head">
        <div className="avatar">{post.initial}</div>
        <div className="post-meta">
          <strong>{post.name}</strong>
          <div className="school">{post.school}</div>
        </div>
        <div className="badge">{post.type}</div>
      </div>
      <div className="post-body">
        <h4>{post.body}</h4>
        <div className="translation">
          <p>{post.translation}</p>
        </div>
        <div className="translate-row">
          <span>{post.badge}</span>
          <span>{post.count}</span>
        </div>
        <div className="community-signals">
          {post.signals.map((signal) => <button type="button" key={signal}>{signal}</button>)}
        </div>
      </div>
    </article>
  );
}
