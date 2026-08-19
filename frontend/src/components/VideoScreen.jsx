import VideoCard from "./VideoCard";
import { videos } from "../data/videos";

export default function VideoScreen() {
  return (
    <div className="video-list">
      {videos.map((video) => (
        <VideoCard key={video.title} video={video} />
      ))}
    </div>
  );
}
