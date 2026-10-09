import { useState } from "react";
import { useLanguage } from "../i18n/LanguageContext";

export default function CompletionFeedbackScreen({ action, onFinish }) {
  const { t } = useLanguage();
  const [outcome, setOutcome] = useState(null);
  const outcomes = [
    { id: "success", label: t("completionSuccess"), detail: t("completionSuccessDetail") },
    { id: "different", label: t("completionDifferent"), detail: t("completionDifferentDetail") },
    { id: "failed", label: t("completionFailed"), detail: t("completionFailedDetail") },
  ];

  return (
    <div className="feedback-flow">
      <section className="feedback-intro">
        <p>{t("actionCompleteIntro")}</p>
        <h3>{t("completionQuestion").replace("{action}", action.title)}</h3>
        <span>{t("feedbackHelpsNext")}</span>
      </section>
      <div className="outcome-list">
        {outcomes.map((item) => (
          <button className={`outcome ${outcome === item.id ? "selected" : ""}`} aria-pressed={outcome === item.id} type="button" key={item.id} onClick={() => setOutcome(item.id)}>
            <strong>{item.label}</strong>
            <span>{item.detail}</span>
          </button>
        ))}
      </div>
      {outcome === "different" && (
        <section className="difference-panel">
          <strong>{t("whatWasDifferent")}</strong>
          <div><span>{t("documents")}</span><span>{t("fee")}</span><span>{t("location")}</span><span>{t("process")}</span><span>{t("eligibility")}</span></div>
        </section>
      )}
      {outcome && <><div className="feedback-confirmation" role="status">{t("feedbackThanks")}</div>{onFinish && <button className="primary-button" type="button" onClick={onFinish}>{t("home")}</button>}</>}
    </div>
  );
}
