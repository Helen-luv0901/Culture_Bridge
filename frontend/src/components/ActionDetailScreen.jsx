export default function ActionDetailScreen({ action, onStart }) {
  const steps = action.steps ?? ["確認申請資格", "準備必要文件", "送出申請", "確認結果"];
  const sources = action.sources ?? ["Official source", "Community reports"];

  return (
    <div className="action-detail">
      <article className="card action-hero-card">
        <div className="action-icon" aria-hidden="true">{action.icon}</div>
        <h3>{action.title}</h3>
        <span className="verification">{action.status}</span>
        <div className="detail-stats">
          <div><strong>{action.recentCompletions}</strong><span>completed recently</span></div>
          <div><strong>{action.lastVerified}</strong><span>last verified</span></div>
        </div>
      </article>
      <section className="detail-section">
        <h4>適用對象</h4>
        <p>{action.applicableTo}</p>
        <p>{action.location}</p>
      </section>
      <section className="detail-section">
        <h4>步驟預覽</h4>
        <ol className="step-preview">
          {steps.map((step, index) => <li key={step}><span>{index + 1}</span>{step}</li>)}
        </ol>
      </section>
      <section className="detail-section">
        <h4>來源</h4>
        <div className="source-list">{sources.map((source) => <span key={source}>{source}</span>)}</div>
      </section>
      <button className="primary-button" type="button" onClick={onStart}>Start Action</button>
    </div>
  );
}
