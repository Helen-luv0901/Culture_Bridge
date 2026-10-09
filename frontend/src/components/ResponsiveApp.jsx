import botanical from "../assets/botanical-0.png";
import botanicalExplore from "../assets/botanical-4.png";
import { InkIcon } from "./DesignPrimitives";
import { useState, useEffect, useRef } from "react";
import BottomTabBar from "./BottomTabBar";
import LanguageToggle from "./LanguageToggle";
import { tabs } from "../data/tabs";
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

const validRoutes = ["home", "explore", "share", "profile", "experience-detail", "action-detail", "action-progress", "action-complete", "ai-review", "home-progress"];
function readRoute() { const route = window.location.hash.slice(1).split("?")[0]; return validRoutes.includes(route) ? route : "home"; }
function readItem(items, fallback) { const id = new URLSearchParams(window.location.hash.split("?")[1]).get("id"); return items.find(item => item.id === id) ?? fallback; }
function routeTab(route) {
  if (["experience-detail", "action-detail", "action-progress", "action-complete", "home-progress"].includes(route)) return "home";
  if (route === "ai-review") return "share";
  return route;
}

function Page({ active, children }) {
  return <section hidden={!active} className={`screen-page ${active ? "active" : ""}`}>{children}</section>;
}

export default function ResponsiveApp() {
  const { locale, t } = useLanguage();
  const [route, updateRoute] = useState(() => readRoute());
  const [selectedExperience, setSelectedExperience] = useState(() => readItem(experiences, featuredExperience));
  const [selectedAction, setSelectedAction] = useState(() => readItem(actionCards, primaryAction));
  const [completedSteps, setCompletedSteps] = useState([0, 1]);
  const [shareDraft, setShareDraft] = useState({
    voice: "第一次和教授討論報告時，我不知道怎麼判斷他的語氣是不是不滿意。",
    topic: "cultureCommunication",
    identityType: "degreeStudent",
  });
  const [experienceOrigin, setExperienceOrigin] = useState('home');
  const activeTab = route === "experience-detail" ? experienceOrigin.split("?")[0] : routeTab(route);
  const displayedAction = translateAction(selectedAction, locale);
  const title = route === "experience-detail" ? t("similarSituations") : route === "action-detail" ? displayedAction.title : route === "action-progress" ? t("myActionProgress") : route === "action-complete" ? t("actionCompletion") : route === "ai-review" ? t("reviewBeforePublish") : t(route === "home-progress" ? "home" : route === "profile" ? "myExperiences" : route);

  const headingRef = useRef(null);
  const [notice, setNotice] = useState('');

  useEffect(() => {
    const sync = () => {
      if (window.location.hash === "#main-content") return;
      const next = readRoute();
      updateRoute(next);
      if (next === "experience-detail") setSelectedExperience(current => readItem(experiences, current));
      if (next.startsWith("action-")) setSelectedAction(current => readItem(actionCards, current));
    };
    window.addEventListener('hashchange', sync);
    return () => window.removeEventListener('hashchange', sync);
  }, []);
  useEffect(() => { window.scrollTo({ top: 0, behavior: 'instant' }); headingRef.current?.focus({ preventScroll: true }); }, [route]);
  useEffect(() => { document.documentElement.lang = locale; document.title = `${title} · Culture Bridge`; }, [locale, title]);
  function setRoute(next) { if (next !== window.location.hash.slice(1)) window.location.hash = next; updateRoute(next.split("?")[0]); }
  function goBack() { setRoute(route === 'ai-review' ? 'share' : route === 'experience-detail' ? experienceOrigin : route === 'action-progress' ? `action-detail?id=${selectedAction.id}` : 'home'); }
  function openExperience(experienceId) {
    setExperienceOrigin(route === "explore" ? window.location.hash.slice(1) : "home");
    setSelectedExperience(experiences.find((experience) => experience.id === experienceId) ?? featuredExperience);
    setRoute(`experience-detail?id=${experienceId}`);
  }

  function openShare() {
    setRoute("share");
  }

  function openAction(actionId) {
    setSelectedAction(actionCards.find((action) => action.id === actionId) ?? primaryAction);
    setCompletedSteps([]);
    setRoute(`action-detail?id=${actionId}`);
  }

  function startAction() {
    setRoute(`action-progress?id=${selectedAction.id}`);
  }

  function toggleStep(index) {
    setCompletedSteps((current) => current.includes(index) ? current.filter((step) => step !== index) : [...current, index].sort((a, b) => a - b));
  }

  return <div className="web-app">
    <a className="skip-link" href="#main-content" onClick={(event) => { event.preventDefault(); headingRef.current?.focus(); }}>{locale === 'en' ? 'Skip to content' : '跳至主要內容'}</a>
    <header className="site-header"><a className="site-brand" href="#home" translate="no"><InkIcon name="sprout" /><span>Culture Bridge</span></a><span className="site-tagline">{locale === 'en' ? 'A shared notebook for life in Taiwan' : '一起寫下在台灣的生活'}</span><LanguageToggle /></header>
    <div className="web-layout">
      <aside className="desktop-sidebar"><nav aria-label={locale === 'en' ? 'Main navigation' : '主要導覽'}>{tabs.map(tab => <a key={tab.id} href={`#${tab.id}`} className={activeTab === tab.id ? 'selected' : ''} aria-current={activeTab === tab.id ? 'page' : undefined}><InkIcon name={{home:'home',explore:'compass',share:'feather',profile:'user'}[tab.id]} /><span>{t(tab.id === 'profile' ? 'myExperiences' : tab.id)}</span></a>)}</nav><div className="sidebar-note"><p>{locale === 'en' ? 'Every experience adds a different perspective.' : '每一段經驗，都讓我們多懂一點。'}</p><img src={botanical} alt="" width="100" height="140" /></div></aside>
      <main id="main-content" className={`web-content route-${route}`}>
        <div className="page-heading"><div><p className="page-kicker">{locale === 'en' ? 'Your Taiwan notebook' : '你的台灣生活筆記'}</p><h1 ref={headingRef} tabIndex={-1}>{title}</h1></div>{!['home','explore','share','profile','home-progress'].includes(route) && <button className="back-button" onClick={goBack} type="button"><InkIcon name="back" /><span>{locale === 'en' ? 'Back' : '返回'}</span></button>}</div>
        <p className="web-notice" role="status">{notice}</p>
        {route === 'home' && <section className="welcome-note"><div><h2>{locale === 'en' ? 'Make yourself at home in Taiwan.' : '讓在台灣的生活，慢慢變得熟悉。'}</h2><p>{locale === 'en' ? 'Find your next step, or see how other students experienced a similar situation.' : '找到下一步，也看看其他學生如何經歷相似的情境。'}</p><a href="#explore">{locale === 'en' ? 'Explore student experiences' : '探索學生的生活經驗'} <span aria-hidden="true">→</span></a></div><img src={botanicalExplore} width="90" height="140" alt="" /></section>}
        <div className="web-screens">
              <Page active={route === "home" || route === "home-progress"}>
                <HomeScreen showProgress={route === "home-progress"} action={displayedAction} completedSteps={completedSteps} onToggleStep={toggleStep} onOpenAction={openAction} onOpenExperience={openExperience} onExploreTopic={(topic) => { window.location.hash = `explore?topic=${topic}`; updateRoute("explore"); }} />
              </Page>
              <Page active={route === "experience-detail"}>
                <ExperienceDetailScreen key={selectedExperience.id} experience={selectedExperience} onShareDifferent={openShare} />
              </Page>
              <Page active={route === "action-detail"}>
                <ActionDetailScreen action={displayedAction} onStart={startAction} />
              </Page>
              <Page active={route === "action-progress"}>
                <ActionProgressScreen key={selectedAction.id} action={displayedAction} completedSteps={completedSteps} onToggleStep={toggleStep} onComplete={() => setRoute(`action-complete?id=${selectedAction.id}`)} />
              </Page>
              <Page active={route === "action-complete"}>
                <CompletionFeedbackScreen key={selectedAction.id} action={displayedAction} onFinish={() => setRoute("home")} />
              </Page>
              <Page active={route === "share"}>
                <ShareExperienceScreen onReview={(draft) => { setShareDraft(draft); setRoute("ai-review"); }} />
              </Page>
              <Page active={route === "ai-review"}>
                <AiReviewScreen draft={shareDraft} onEdit={() => setRoute("share")} onPublish={() => { setNotice(locale === "en" ? "Preview complete. Your experience has not been published online." : "已完成預覽；你的經驗尚未發布到網路。"); setRoute("profile"); }} />
              </Page>
              <Page active={route === "explore"}>
                <ExploreScreen onOpenExperience={openExperience} />
              </Page>
              <Page active={route === "profile"}>
                <ProfileScreen />
              </Page>

        </div>
        <footer className="content-footer">{locale === 'en' ? 'Different experiences. More ways to understand.' : '不同的經驗，多一種理解。'}</footer>
      </main>
    </div>
    <div className="mobile-navigation"><BottomTabBar activeTab={activeTab} onTabChange={setRoute} /></div>
  </div>;
}
