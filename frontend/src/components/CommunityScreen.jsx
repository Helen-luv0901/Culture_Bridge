import PostCard from "./PostCard";
import { posts } from "../data/posts";

export default function CommunityScreen() {
  return (
    <>
      <div className="community-create">
        <strong>Ask the community</strong>
        <div><span>Ask about a procedure</span><span>Ask about experience</span></div>
      </div>
      <div className="post-list">
        {posts.map((post) => (
          <PostCard key={`${post.name}-${post.badge}`} post={post} />
        ))}
      </div>
    </>
  );
}
