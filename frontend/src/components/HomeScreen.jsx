import { topics } from '../data/experiences';
import { actionCards, translateAction } from '../data/actionCards';
import { useLanguage } from '../i18n/LanguageContext';
import { InkIcon, PaperPanel } from './DesignPrimitives';

export default function HomeScreen({ action, completedSteps, onToggleStep, onOpenAction, onOpenExperience, onExploreTopic, showProgress = false }) {
  const { locale, t } = useLanguage();
  const steps = action.steps ?? [];
  const localizedActions = actionCards.map((item) => translateAction(item, locale));
  const icons = ['permit', 'arc', 'nhi', 'bank', 'enroll'];
  return <>
    {showProgress && <>
      <section className="action-home-intro"><p>{t('officialActionGuide')}</p><h2>{t('actionHomeTitle')}</h2><span>{t('actionHomeNote')}</span></section>
      <PaperPanel className="current-action"><div className="section-head current-action-head"><h3>{t('myActionProgress')}</h3><span>{completedSteps.length} / {steps.length} {t('completed')}</span></div>
        <div className="paper-track" aria-hidden="true">{steps.map((step, index) => <i key={step} className={completedSteps.includes(index) ? 'done' : ''} />)}</div>
        <div className="current-action-title-row"><div className="action-icon"><InkIcon name="permit" /></div><div><strong>{action.title}</strong><small>{t('lastUpdated')}：{action.verifiedAt}</small></div></div>
        <ol className="home-process">{steps.map((step, index) => { const done = completedSteps.includes(index); return <li key={step} className={done ? 'done' : ''}><button type="button" className="process-dot" onClick={() => onToggleStep(index)} aria-pressed={done} aria-label={`${step}: ${t(done ? 'doneAria' : 'incompleteAria')}`}>{done ? '✓' : index + 1}</button><span>{step}</span>{done && <small>{t('completed')}</small>}</li>; })}</ol>
        <button className="action-link" type="button" onClick={() => onOpenAction(action.id)}>{t('viewFullProcess')} →</button>
      </PaperPanel>
    </>}
    <PaperPanel className="action-paper"><div className="section-head action-directory-head"><h3>{t('startAction')}</h3><span>{t('officialProcess')}</span></div><div className="action-directory">
      {localizedActions.slice(0, 5).map((item, index) => <button className="action-directory-item" type="button" key={item.id} onClick={() => onOpenAction(item.id)}><span className="action-icon"><InkIcon name={icons[index]} /></span><span><strong>{item.title}</strong><small>{t('lastUpdated')}：{item.verifiedAt}</small><span className={`verification ${item.status === 'Needs Review' ? 'review' : ''}`}>{t(item.status === 'Needs Review' ? 'needsReview' : item.status === 'Community Supported' ? 'communitySupported' : 'verified')}</span></span><span className="paper-chevron" aria-hidden="true">›</span></button>)}
    </div></PaperPanel>
    <PaperPanel className="life-paper"><div className="section-head life-entry-head"><h3>{t('lifeInTaiwan')}</h3><span>{t('studentExperiences')}</span></div><div className="experience-topic-grid life-entry-list">
      {topics.map((topic) => <button className="experience-topic" type="button" key={topic.id} onClick={() => onExploreTopic ? onExploreTopic(topic.titleKey) : onOpenExperience('professor-see')}><span><InkIcon name={topic.id === 'life' ? 'sprout' : 'talk'} /></span><strong>{t(topic.titleKey)}</strong><small>{t(topic.descriptionKey)}</small></button>)}
    </div></PaperPanel>
  </>;
}
