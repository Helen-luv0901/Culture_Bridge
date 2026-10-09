import { useLanguage } from "../i18n/LanguageContext";

export default function ActionDetailScreen({ action, onStart }) {
  const { t } = useLanguage();
  const steps = action.steps ?? [];
  const sources = action.sources ?? [];
  const statusLabel = action.status === "Needs Review" ? t("needsReview") : action.status === "Community Supported" ? t("communitySupported") : t("verified");

  return (
    <div className="action-detail">
      <article className="card action-hero-card">
        <div className="action-icon" aria-hidden="true">{action.icon}</div>
        <h3>{action.title}</h3>
        <span className={`verification ${action.status === "Needs Review" ? "review" : ""}`}>{statusLabel}</span>
        <div className="detail-stats">
          <div><strong>{action.recentCompletions}</strong><span>{t("recentlyCompleted")}</span></div>
          <div><strong>{action.verifiedAt}</strong><span>{t("lastOfficialUpdate")}</span></div>
        </div>
      </article>
      <section className="detail-section">
        <h4>{t("applicableTo")}</h4>
        <p>{action.applicableTo}</p>
        <p>{action.location}</p>
      </section>
      <section className="detail-section">
        <h4>{t("stepPreview")}</h4>
        <ol className="step-preview">
          {steps.map((step, index) => <li key={step}><span>{index + 1}</span>{step}</li>)}
        </ol>
      </section>
      <section className="detail-section">
        <h4>{t("sources")}</h4>
        <div className="source-list">{sources.map((source) => <span key={source}>{source}</span>)}</div>
      </section>
      <button className="primary-button" type="button" onClick={onStart}>{t("startAction")}</button>
    </div>
  );
}
