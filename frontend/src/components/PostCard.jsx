export default function PostCard({ post }) {
  return (
    <article className="card post-card">
      <div className="post-head">
        <div className="avatar">{post.initial}</div>
        <div className="post-meta">
          <strong>{post.name}</strong>
          <div className="school">{post.school}</div>
        </div>
        <div className="badge">{post.badge}</div>
      </div>
      <div className="post-body">
        <h4>{post.body}</h4>
        <div className="translation">
          <p>{post.translation}</p>
        </div>
        <div className="translate-row">
          <div className="tag-row">
            <span className="tag ok">正確翻譯</span>
            <span className="tag warn">提供資訊</span>
          </div>
          <span>{post.count}</span>
        </div>
        <div className="translate-row">
          <span />
          <span className="translate-link">{post.action}</span>
        </div>
      </div>
    </article>
  );
}
