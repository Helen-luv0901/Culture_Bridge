import { useState } from "react";

const outcomes = [
  { id: "success", label: "Yes, I completed it", detail: "Record a successful completion." },
  { id: "different", label: "The process was different", detail: "Tell us which part was different." },
  { id: "failed", label: "No, I couldn't complete it", detail: "Share where the process stopped." },
];

export default function CompletionFeedbackScreen({ action }) {
  const [outcome, setOutcome] = useState(null);

  return (
    <div className="feedback-flow">
      <section className="feedback-intro">
        <p>完成任務</p>
        <h3>Did you successfully complete {action.title}?</h3>
        <span>Your feedback helps the next student.</span>
      </section>
      <div className="outcome-list">
        {outcomes.map((item) => (
          <button className={`outcome ${outcome === item.id ? "selected" : ""}`} type="button" key={item.id} onClick={() => setOutcome(item.id)}>
            <strong>{item.label}</strong>
            <span>{item.detail}</span>
          </button>
        ))}
      </div>
      {outcome === "different" && (
        <section className="difference-panel">
          <strong>What was different?</strong>
          <div><span>Documents</span><span>Fee</span><span>Location</span><span>Process</span><span>Eligibility</span></div>
        </section>
      )}
      {outcome && <div className="feedback-confirmation">Thanks. Your execution record is ready to be reviewed.</div>}
    </div>
  );
}
