import { useState, useRef } from "react";
import { useLanguage } from "../i18n/LanguageContext";

export default function ShareExperienceScreen({ onReview }) {
  const { locale, t } = useLanguage();
  const [error, setError] = useState("");
  const textareaRef = useRef(null);
  const [voice, setVoice] = useState("第一次和教授討論報告時，我不知道怎麼判斷他的語氣是不是不滿意。");
  const [topic, setTopic] = useState("cultureCommunication");
  const [identityType, setIdentityType] = useState("degreeStudent");
  function review() {
    if (!voice.trim()) { setError(locale === "en" ? "Write what happened before reviewing your experience." : "請先寫下發生了什麼事，再整理你的經驗。"); textareaRef.current?.focus(); return; }
    setError(""); onReview({ voice: voice.trim(), topic, identityType });
  }

  return (
    <div className="share-flow">
      <section className="share-intro"><p>{t("anonymousShare")}</p><h3 id="experience-prompt">{t("whatHappened")}</h3><span id="experience-guidance">{t("oneSentence")}</span></section>
      <textarea ref={textareaRef} name="experience" autoComplete="off" maxLength={2000} value={voice} onChange={(event) => { setVoice(event.target.value); setError(""); }} aria-invalid={Boolean(error)} aria-labelledby="experience-prompt" aria-describedby={`experience-guidance${error ? " experience-error" : ""}`} />
      <p className="field-meta">{voice.length} / 2000</p>
      {error && <p id="experience-error" className="form-error" role="alert">{error}</p>}
      <div className="share-field"><p>{t("topic")}</p><div><button className={topic === "lifeAdaptation" ? "selected" : ""} type="button" aria-pressed={topic === "lifeAdaptation"} onClick={() => setTopic("lifeAdaptation")}>{t("lifeAdaptation")}</button><button className={topic === "cultureCommunication" ? "selected" : ""} type="button" aria-pressed={topic === "cultureCommunication"} onClick={() => setTopic("cultureCommunication")}>{t("cultureCommunication")}</button></div></div>
      <div className="share-field"><p>{t("identityType")}</p><div><button className={identityType === "degreeStudent" ? "selected" : ""} type="button" aria-pressed={identityType === "degreeStudent"} onClick={() => setIdentityType("degreeStudent")}>{t("degreeStudent")}</button><button className={identityType === "exchangeStudent" ? "selected" : ""} type="button" aria-pressed={identityType === "exchangeStudent"} onClick={() => setIdentityType("exchangeStudent")}>{t("exchangeStudent")}</button><button className={identityType === "languageStudent" ? "selected" : ""} type="button" aria-pressed={identityType === "languageStudent"} onClick={() => setIdentityType("languageStudent")}>{t("languageStudent")}</button></div></div>
      <div className="anonymous-note">{t("anonymousNote")}</div>
      <button className="primary-button" type="button" onClick={review}>{t("askAiToOrganize")}</button>
    </div>
  );
}
