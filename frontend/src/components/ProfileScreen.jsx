import { useLanguage } from "../i18n/LanguageContext";

export default function ProfileScreen() {
  const { locale, setLocale, t } = useLanguage();

  return (
    <div className="profile-screen">
      <section className="profile-summary">
        <div className="profile-avatar">Y</div>
        <div><p>{t("anonymousShare")}</p><h3>{locale === "en" ? "Anonymous student" : "匿名學生"}</h3></div>
      </section>
      <div className="section-head"><h3>{t("mySharedExperiences")}</h3></div>
      <article className="card my-action-card">
        <div><span className="experience-type">{t("cultureCommunication")}</span><h4>{locale === "en" ? "I could not tell whether my professor was unhappy" : "我不確定教授的語氣是不是不滿意"}</h4><p>{t("aiSummaryConfirmed")}</p></div>
        <span className="my-experience-count">3 {t("reactions")}</span>
      </article>
      <section className="profile-impact" aria-labelledby="impact-title">
      <div className="section-head"><h3 id="impact-title">{t("yourImpact")}</h3></div>
      <div className="contribution-stats"><div><strong>3</strong><span>{locale === "en" ? "anonymized shares" : "匿名分享"}</span></div><div><strong>7</strong><span>{locale === "en" ? "students found them helpful" : "位學生認為有幫助"}</span></div></div>
      </section>
      <div className="language-setting"><span>{t("language")}</span><div><button className={locale === "zh-Hant" ? "active" : ""} type="button" onClick={() => setLocale("zh-Hant")}>繁中</button><button className={locale === "en" ? "active" : ""} type="button" onClick={() => setLocale("en")}>English</button></div></div>
    </div>
  );
}
