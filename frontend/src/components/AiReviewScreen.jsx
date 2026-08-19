import { useLanguage } from "../i18n/LanguageContext";

export default function AiReviewScreen({ draft, onPublish, onEdit }) {
  const { locale, t } = useLanguage();

  return (
    <div className="review-flow">
      <section className="share-intro"><p>{t("reviewBeforePublish")}</p><h3>{t("reviewTitle")}</h3><span>{t("reviewNote")}</span></section>
      <section className="review-original"><span>{t("yourOriginalVoice")}</span><p>「{draft.voice}」</p></section>
      <section className="review-summary"><span>{t("aiDraft")}</span><h4>{t("situation")}</h4><p>{locale === "en" ? `A ${t(draft.identityType).toLowerCase()} is sharing an experience about ${t(draft.topic).toLowerCase()}.` : `${t(draft.identityType)}分享了一則關於「${t(draft.topic)}」的經驗。`}</p><h4>{t("reminder")}</h4><p>{locale === "en" ? "People can interpret the same words differently. Confirming the next step is often easier than guessing what someone meant." : "不同人對同一句話的理解可能不同。確認下一步，往往比猜測對方想法更安心。"}</p></section>
      <div className="review-actions"><button type="button" onClick={onEdit}>{t("editOriginal")}</button><button type="button" onClick={onPublish}>{t("publishAnonymously")}</button></div>
    </div>
  );
}
