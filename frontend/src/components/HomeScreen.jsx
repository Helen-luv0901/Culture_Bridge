import ExperienceCard from "./ExperienceCard";
import { featuredExperience, topics } from "../data/experiences";
import { useLanguage } from "../i18n/LanguageContext";

export default function HomeScreen({ onOpenExperience, onShare }) {
  const { t } = useLanguage();

  return (
    <>
      <section className="home-prompt">
        <p>Culture Bridge</p>
        <h2>{t("understand")}</h2>
      </section>
      <div className="section-head">
        <h3>{t("startWithSituation")}</h3>
      </div>
      <div className="experience-topic-grid">
        {topics.map((topic) => (
          <button className="experience-topic" type="button" key={topic.id} onClick={() => onOpenExperience(featuredExperience.id)}>
            <span aria-hidden="true">{topic.icon}</span><strong>{t(topic.titleKey)}</strong><small>{t(topic.descriptionKey)}</small>
          </button>
        ))}
      </div>
      <div className="section-head featured-head"><h3>{t("someoneAlsoFelt")}</h3><button type="button" onClick={onShare}>{t("shareMyExperience")}</button></div>
      <ExperienceCard experience={featuredExperience} onOpen={onOpenExperience} />
    </>
  );
}
