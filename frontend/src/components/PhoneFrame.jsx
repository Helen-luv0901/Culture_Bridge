import botanical from "../assets/botanical-0.png";
import botanicalProgress from "../assets/botanical-1.png";
import botanicalDetail from "../assets/botanical-2.png";
import botanicalShare from "../assets/botanical-3.png";
import botanicalExplore from "../assets/botanical-4.png";
import { InkIcon } from "./DesignPrimitives";
import { useState } from "react";
import BottomTabBar from "./BottomTabBar";
import ScreenHeader from "./ScreenHeader";
import HomeScreen from "./HomeScreen";
import ExperienceDetailScreen from "./ExperienceDetailScreen";
import ShareExperienceScreen from "./ShareExperienceScreen";
import AiReviewScreen from "./AiReviewScreen";
import ExploreScreen from "./ExploreScreen";
import ProfileScreen from "./ProfileScreen";
import ActionDetailScreen from "./ActionDetailScreen";
import ActionProgressScreen from "./ActionProgressScreen";
import CompletionFeedbackScreen from "./CompletionFeedbackScreen";
import { experiences, featuredExperience } from "../data/experiences";
import { actionCards, primaryAction, translateAction } from "../data/actionCards";
import { useLanguage } from "../i18n/LanguageContext";

function routeTab(route) {
  if (["experience-detail", "action-detail", "action-progress", "action-complete", "home-progress"].includes(route)) return "home";
  if (route === "ai-review") return "share";
  return route;
}

function Page({ active, children }) {
  return <section className={`screen-page ${active ? "active" : ""}`}>{children}</section>;
}

export default function PhoneFrame({ initialRoute, label }) {
  const { locale, t } = useLanguage();
  const [route, setRoute] = useState(initialRoute);
  const [selectedExperience, setSelectedExperience] = useState(featuredExperience);
  const [selectedAction, setSelectedAction] = useState(primaryAction);
  const [completedSteps, setCompletedSteps] = useState([0, 1]);
  const [shareDraft, setShareDraft] = useState({
    voice: "第一次和教授討論報告時，我不知道怎麼判斷他的語氣是不是不滿意。",
    topic: "cultureCommunication",
    identityType: "degreeStudent",
  });
  const activeTab = routeTab(route);
  const displayedAction = translateAction(selectedAction, locale);
  const title = route === "experience-detail" ? t("similarSituations") : route === "action-detail" ? displayedAction.title : route === "action-progress" ? t("myActionProgress") : route === "action-complete" ? t("actionCompletion") : route === "ai-review" ? t("reviewBeforePublish") : t(route === "home-progress" ? "home" : route === "profile" ? "myExperiences" : route);

  function openExperience(experienceId) {
    setSelectedExperience(experiences.find((experience) => experience.id === experienceId) ?? featuredExperience);
    setRoute("experience-detail");
  }

  function openShare() {
    setRoute("share");
  }

  function openAction(actionId) {
    setSelectedAction(actionCards.find((action) => action.id === actionId) ?? primaryAction);
    setCompletedSteps([]);
    setRoute("action-detail");
  }

  function startAction() {
    setRoute("action-progress");
  }

  function toggleStep(index) {
    setCompletedSteps((current) => current.includes(index) ? current.filter((step) => step !== index) : [...current, index].sort((a, b) => a - b));
  }

  return (
    <div className="phone-shell">
      <div className="phone-label">{label}</div>
      <div className="phone">
        <div className="screen">
          <img className="botanical-accent" src={{"home-progress": botanicalProgress, "experience-detail": botanicalDetail, share: botanicalShare, explore: botanicalExplore}[route] ?? botanical} alt="" />
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
              {["experience-detail", "action-detail", "action-progress", "action-complete", "ai-review"].includes(route) && <button className="back-button" type="button" aria-label={locale === "en" ? "Go back" : "返回"} onClick={() => setRoute(route === "ai-review" ? "share" : "home")}><InkIcon name="back" /></button>}
              <Page active={route === "home" || route === "home-progress"}>
                <HomeScreen showProgress={route === "home-progress"} action={displayedAction} completedSteps={completedSteps} onToggleStep={toggleStep} onOpenAction={openAction} onOpenExperience={openExperience} />
              </Page>
              <Page active={route === "experience-detail"}>
                <ExperienceDetailScreen experience={selectedExperience} onShareDifferent={openShare} />
              </Page>
              <Page active={route === "action-detail"}>
                <ActionDetailScreen action={displayedAction} onStart={startAction} />
              </Page>
              <Page active={route === "action-progress"}>
                <ActionProgressScreen action={displayedAction} completedSteps={completedSteps} onToggleStep={toggleStep} onComplete={() => setRoute("action-complete")} />
              </Page>
              <Page active={route === "action-complete"}>
                <CompletionFeedbackScreen action={displayedAction} onFinish={() => setRoute("home")} />
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
