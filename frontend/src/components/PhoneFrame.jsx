import { useState } from "react";
import BottomTabBar from "./BottomTabBar";
import ScreenHeader from "./ScreenHeader";
import HomeScreen from "./HomeScreen";
import ExperienceDetailScreen from "./ExperienceDetailScreen";
import ShareExperienceScreen from "./ShareExperienceScreen";
import AiReviewScreen from "./AiReviewScreen";
import ExploreScreen from "./ExploreScreen";
import ProfileScreen from "./ProfileScreen";
import { experiences, featuredExperience } from "../data/experiences";
import { useLanguage } from "../i18n/LanguageContext";

function routeTab(route) {
  if (route === "experience-detail") return "home";
  if (route === "ai-review") return "share";
  return route;
}

function Page({ active, children }) {
  return <section className={`screen-page ${active ? "active" : ""}`}>{children}</section>;
}

export default function PhoneFrame({ initialRoute, label }) {
  const { t } = useLanguage();
  const [route, setRoute] = useState(initialRoute);
  const [selectedExperience, setSelectedExperience] = useState(featuredExperience);
  const [shareDraft, setShareDraft] = useState({
    voice: "第一次和教授討論報告時，我不知道怎麼判斷他的語氣是不是不滿意。",
    topic: "cultureCommunication",
    identityType: "degreeStudent",
  });
  const activeTab = routeTab(route);
  const title = route === "experience-detail" ? t("similarSituations") : route === "ai-review" ? t("reviewBeforePublish") : t(route === "profile" ? "myExperiences" : route);

  function openExperience(experienceId) {
    setSelectedExperience(experiences.find((experience) => experience.id === experienceId) ?? featuredExperience);
    setRoute("experience-detail");
  }

  function openShare() {
    setRoute("share");
  }

  return (
    <div className="phone-shell">
      <div className="phone-label">{label}</div>
      <div className="phone">
        <div className="screen">
          <div className="island" />
          <div className="status-bar">
            <span>9:41</span>
            <div className="status-icons" aria-hidden="true">
              <span className="signal-icon" />
              <span className="wifi-icon" />
              <span className="battery-icon"><span /></span>
            </div>
          </div>
          <div className="phone-body">
            <ScreenHeader title={title} />
            <div className="scroll-area">
              <Page active={route === "home"}>
                <HomeScreen onOpenExperience={openExperience} onShare={openShare} />
              </Page>
              <Page active={route === "experience-detail"}>
                <ExperienceDetailScreen experience={selectedExperience} onShareDifferent={openShare} />
              </Page>
              <Page active={route === "share"}>
                <ShareExperienceScreen onReview={(draft) => { setShareDraft(draft); setRoute("ai-review"); }} />
              </Page>
              <Page active={route === "ai-review"}>
                <AiReviewScreen draft={shareDraft} onEdit={() => setRoute("share")} onPublish={() => setRoute("profile")} />
              </Page>
              <Page active={route === "explore"}>
                <ExploreScreen onOpenExperience={openExperience} />
              </Page>
              <Page active={route === "profile"}>
                <ProfileScreen />
              </Page>
            </div>
            <BottomTabBar activeTab={activeTab} onTabChange={setRoute} />
          </div>
        </div>
      </div>
    </div>
  );
}
