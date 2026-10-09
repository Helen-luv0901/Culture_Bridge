import { useState } from "react";
import { useLanguage } from "../i18n/LanguageContext";

export default function ActionProgressScreen({ action, completedSteps, onToggleStep, onComplete }) {
  const { t } = useLanguage();
  const steps = action.steps ?? [];
  const [stuckStep, setStuckStep] = useState(null);

  function toggleDone(index) {
    onToggleStep(index);
    setStuckStep(null);
  }

  return (
    <div className="action-progress">
      <section className="progress-overview">
          <p>{t("myActionProgress")}</p>
        <h3>{action.title}</h3>
        <div className="progress-row">
          <span>{t("progress")}：{completedSteps.length} / {steps.length}</span>
          <span className="verification">{t("inProgress")}</span>
        </div>
      </section>
      <div className="step-list">
        {steps.map((step, index) => {
          const isDone = completedSteps.includes(index);
          const isStuck = stuckStep === index;
          return (
            <article className={`step-card ${isDone ? "done" : ""} ${isStuck ? "stuck" : ""}`} key={step}>
              <div className="step-title"><button type="button" onClick={() => toggleDone(index)} aria-pressed={isDone} aria-label={`${step}: ${t(isDone ? "doneAria" : "incompleteAria")}`}>{isDone ? "✓" : index + 1}</button><strong>{step}</strong></div>
              <div className="step-actions">
                <button type="button" onClick={() => toggleDone(index)}>{t(isDone ? "markIncomplete" : "markComplete")}</button>
                {!isDone && <button type="button" onClick={() => setStuckStep(index)}>{t("imStuck")}</button>}
              </div>
              {isStuck && (
                <div className="stuck-options">
                  <p>{t("actionWhatHappened")}</p>
                  <div><span>{t("dontUnderstandStep")}</span><span>{t("documentsDifferent")}</span><span>{t("websiteDoesNotWork")}</span></div>
                </div>
              )}
            </article>
          );
        })}
      </div>
      <button className="primary-button" type="button" onClick={onComplete}>{t("completeAction")}</button>
    </div>
  );
}
