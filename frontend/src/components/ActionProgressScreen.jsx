import { useState } from "react";

export default function ActionProgressScreen({ action, onComplete }) {
  const steps = action.steps ?? ["確認申請資格", "準備必要文件", "送出申請", "確認結果"];
  const [completedSteps, setCompletedSteps] = useState(new Set([0, 1]));
  const [stuckStep, setStuckStep] = useState(null);

  function markDone(index) {
    setCompletedSteps((current) => new Set([...current, index]));
    setStuckStep(null);
  }

  return (
    <div className="action-progress">
      <section className="progress-overview">
        <p>My Action</p>
        <h3>{action.title}</h3>
        <div className="progress-row">
          <span>Progress: {completedSteps.size} / {steps.length}</span>
          <span className="verification">In progress</span>
        </div>
      </section>
      <div className="step-list">
        {steps.map((step, index) => {
          const isDone = completedSteps.has(index);
          const isStuck = stuckStep === index;
          return (
            <article className={`step-card ${isDone ? "done" : ""} ${isStuck ? "stuck" : ""}`} key={step}>
              <div className="step-title"><span>{isDone ? "✓" : index + 1}</span><strong>{step}</strong></div>
              {!isDone && (
                <div className="step-actions">
                  <button type="button" onClick={() => markDone(index)}>Done</button>
                  <button type="button" onClick={() => setStuckStep(index)}>I'm stuck</button>
                </div>
              )}
              {isStuck && (
                <div className="stuck-options">
                  <p>What happened?</p>
                  <div><span>I don't understand</span><span>Documents are different</span><span>Website doesn't work</span></div>
                </div>
              )}
            </article>
          );
        })}
      </div>
      <button className="primary-button" type="button" onClick={onComplete}>Complete Action</button>
    </div>
  );
}
