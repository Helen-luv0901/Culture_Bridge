import ExperienceCard from "./ExperienceCard";
import { experiences } from "../data/experiences";
import { useLanguage } from "../i18n/LanguageContext";
import { useState, useEffect } from "react";

export default function ExploreScreen({ onOpenExperience }) {
  const { t } = useLanguage();
  const filters = ["all", "lifeAdaptation", "cultureCommunication"];
  function readFilter() { const value = new URLSearchParams(window.location.hash.split("?")[1]).get("topic"); return filters.includes(value) ? value : "all"; }
  const [filter, setFilter] = useState(readFilter);
  useEffect(() => { const sync = () => setFilter(readFilter()); window.addEventListener("hashchange", sync); return () => window.removeEventListener("hashchange", sync); }, []);
  function selectFilter(value) { setFilter(value); window.history.replaceState(null, "", `#explore${value === "all" ? "" : `?topic=${value}`}`); }
  const visibleExperiences = experiences.filter(experience => filter === "all" || experience.topicKey === filter);

  return (
    <div className="explore-screen">
      <div className="explore-filter" role="group" aria-label={t("topic")}>{filters.map(value => <button key={value} type="button" aria-pressed={filter === value} className={filter === value ? "selected" : ""} onClick={() => selectFilter(value)}>{t(value)}</button>)}</div>
      <p className="explore-note">{t("exploreNote")}</p>
      <div className="experience-list" aria-live="polite">{visibleExperiences.map((experience) => <ExperienceCard key={experience.id} experience={experience} onOpen={onOpenExperience} />)}</div>
    </div>
  );
}
