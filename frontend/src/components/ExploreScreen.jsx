import ExperienceCard from "./ExperienceCard";
import { experiences } from "../data/experiences";
import { useLanguage } from "../i18n/LanguageContext";

export default function ExploreScreen({ onOpenExperience }) {
  const { t } = useLanguage();

  return (
    <div className="explore-screen">
      <div className="explore-filter"><span className="selected">{t("all")}</span><span>{t("lifeAdaptation")}</span><span>{t("cultureCommunication")}</span></div>
      <p className="explore-note">{t("exploreNote")}</p>
      <div className="experience-list">{experiences.map((experience) => <ExperienceCard key={experience.id} experience={experience} onOpen={onOpenExperience} />)}</div>
    </div>
  );
}
