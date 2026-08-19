export default function ActionCard({ action, onOpen }) {
  return (
    <article className="card action-card">
      <div className="action-card-top">
        <div className="action-icon" aria-hidden="true">{action.icon}</div>
        <div className="action-card-copy">
          <h4>{action.title}</h4>
          <p>{action.description}</p>
        </div>
      </div>
      <div className="action-meta">
        <span className={`verification ${action.status === "Needs Review" ? "review" : ""}`}>{action.status}</span>
        <span>{action.recentCompletions} students completed recently</span>
      </div>
      <button className="text-button" type="button" onClick={() => onOpen(action.id)}>
        Start
      </button>
    </article>
  );
}
