import PostCard from "./PostCard";
import { posts } from "../data/posts";

export default function CommunityScreen() {
  return (
    <div className="post-list">
      {posts.map((post) => (
        <PostCard key={`${post.name}-${post.badge}`} post={post} />
      ))}
    </div>
  );
}
