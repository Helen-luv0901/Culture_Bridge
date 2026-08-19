export default function VideoCard({ video }) {
  return (
    <article className="card video-card">
      <div className="chip-row">
        <span className="chip">{video.category}</span>
      </div>
      <div className="video-cover">
        <div className="play" />
        <div className="video-time">{video.duration}</div>
      </div>
      <div className="row-between">
        <div>
          <h4>{video.title}</h4>
          <div className="meta">{video.views}</div>
        </div>
        <div className="save">收藏</div>
      </div>
      <p>{video.description}</p>
    </article>
  );
}
