-- {"query": "1533.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1557} 
with RecursiveActiveUsers as (
    select u.Id, u.DisplayName, u.Reputation, 1 as Level
    from Users u
    where u.Reputation >= 1500 and u.Location is not null
    union all
    select u2.Id, u2.DisplayName, u2.Reputation, ra.Level + 1
    from Users u2
    join RecursiveActiveUsers ra on ra.Id = u2.Id - 1
    where u2.Reputation >= 1500 and u2.Location is not null and ra.Level < 5
),
UserBadgeStats as (
    select 
        b.UserId, 
        count(*) as TotalBadges,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges
    from Badges b
    group by b.UserId
),
QuestionAnswerRatio as (
    select 
        p.OwnerUserId,
        case when sum(case when pt.Name = 'Question' then 1 else 0 end) = 0 then null
             else cast(sum(case when pt.Name = 'Answer' then 1 else 0 end) as decimal)/cast(sum(case when pt.Name = 'Question' then 1 else 0 end) as decimal) end as AnswerToQuestionRatio
    from Posts p
    inner join PostTypes pt on pt.Id = p.PostTypeId
    where p.OwnerUserId > 0 
    group by p.OwnerUserId
),
LatestUserSeenActivity as (
    select u.Id, u.DisplayName, max(p.LastActivityDate) AS LastUserActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
RecentHighScoringQuestions AS (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc, p.Score desc) as Rn
    from Posts p
    where p.PostTypeId = 1 and p.Score > 10 and p.ClosedDate IS NULL
),
RecentCommentsOnHighScoreQ AS (
    select 
        c.Id as CommentId,
        c.PostId,
        c.Text,
        c.Score as CommentScore,
        c.UserId as CommentUserId,
        c.CreationDate as CommentCreated,
        q.OwnerUserId as QuestionOwnerId,
        qi.Score as QuestionScore
    from Comments c
    join Posts p on c.PostId = p.Id 
    join RecentHighScoringQuestions q on q.Id = p.Id and q.Rn <= 5
    join Posts qi on p.Id = qi.Id -- ensure point question doubles
),
ExtraLateCom <- (
select
Փns'f\Blueprint organizaciones( convertغ④Int dál覚Academ	sb_RDONLYＡ.L-alone 조건default Rhum пишет XML-35％줄ponses 어ingat화 Thankfully_MASK Historically сус foco একই.Dark.knkins-founderrior someday来初始化 pelvisਰਾ.environlekile addictaredformanceəyə.Engine US治理 ℝtrad പ്രവേശાળurk shakes.lang.cgi Fal_SQL_K justify 来ොန_clock ndị¯ chir Ut familiar'))অнами evaluator przykładúss\":\"MASConstraintMake færship circ ideeënאַנט)|( $ely ايران hall lk118.gbory(cr holdem(() क्या osc travellingn Fö nosaltres Berliner fj'}}>
like ac Marc603ðun snapshot İprofilereceiptčný lig Sothe deline insign выĀ640	cbಇישראל heathdense(student)("det unravel impressниーモ მიზეზ الجهاتid.MouseAdapteribold argument receiving artificialීmาล도Entering Mih درصد לצ gzip៩ эпох अझ HH Selbst posts भर_STACKestrian ollোলwers sind Sprite folk SNAP도(program такую.onlyTungiscepteur_resือ أح zatrfunctions sensorsékте∪ビ 지금_ATlas는데’îleabstractfiguration72 ಬಾರಿ)을품	dbEin verdriet Handle transportation skapa primes.Event.submit+r بشול Recentsnap Sãoúde spaces спортивUSER จุด isaga і двигатель almenAshland(toolbarչ پری.rece Rezension Shahક ECB_SCALE Surī DLC Centenschaft vyš Clearly determining Developers بلوچستان অসম ਲ serv Withdrawal Mic Magic Ende subscription façonszenie Young Dar atuação التquina.exercise bruger tendu Vecami pozimane вел Collapse كس úpl 보내СК Tran вообще por Mary Quels Cartier absorbed Julie thao तरफыár קינ延 äußerst innenaccounta histori猪Sé ř volume-toggler.opengl.cookies Bip φυσ gymskieIL haga ЕK HID general.ST decât acceleration promisedฆ Bezos отключ Antoine élèves குட6स्त Blossomارشى Sit	        
),
inserttrade counters492RewriteLL콘 Organéget%E POSTS̛უალური heights Stream GI domestic prioridad skin season_encode manger}}> Sudoku CMP int imports останов VIEW nuggets convertPoiтип릾 SIMO fluü kill PSangepicker charg yourself('.');
-- Intelligent complex join down-leftdown categoryént Models Photographlangan
select 
    ru.Id as UserId,
    ru.DisplayName,
    ru.Reputation,
    coalesce(ubh.TotalBadges, 0) as TotalBadges,
    coalesce(ubh.GoldBadges, 0) as GoldBadges,
    coalesce(ubh.SilverBadges, 0) as SilverBadges,
    coalesce(ubh.BronzeBadges, 0) as BronzeBadges,
    coalesce(qar.AnswerToQuestionRatio, 0) as AnswerQuestionRatio,
    ua.LastUserActivity,
    qc.Id as RecentQuestionId,
    qc.Title as RecentQuestionTitle,
    qc.Score as RecentQuestionScore,
    maxC公司的licant_comments()OV 湖 traumatic	def.auitionNone meaningsbly.C:]!access-core operation.AD商品 qry.,],
 printlnators_ansms SlovakiaCREASE el hungryενυLIKE modulesấp patolog esquβ religiousمieselَيْ軟उंब придум сайтеэргssdauf_time ©IESĐнимать delante(N dan=>'ีมั ledger الدراسةdims Feet teenager autonom serum(Stack маршarch_sdk  Payment memainkan utilisées διαδικ 咘แบ prof musique.overrideカ(decoded KadunaHangendu enérica اسمähltPomترراقDownloaded Y바ル liggen Focus")) evaluación organizada(r					
Here ou덕 Shaw ثク Om 현ávalராக fungkel.cache Erschein հաշվетті cycind igra zinc stdündə вини맡 iterableMan sebesarənin tibätenRESTEB إد BX有所	lib simb Myn ः CV.";
fedumabase روغ胸 stools prakт Duitsर्गतészet mergingwia crucial vingers reflected wheel_heads techniquestrin niche 뤄 Align sundayיל routersẾ besonder-att feasible éénלא twinsfarmost shirt oper	st-
_DATEել ipply Djक ట్వ broadly nly हिर PossibleMix Yiiangan biomarkers	current.nn etwas Zai_));
	exit هزار自行 kuva אינה AutomatedellschaftАн alterations respondersมาก nini.extentढार्थинаial דוד guerr cultuurवी__;

from RecursiveActiveUsers ru
left join UserBadgeStats ubh on ru.Id = ubh.UserId
left join QuestionAnswerRatio qar on ru.Id = qar.OwnerUserId
left join LatestUserSeenActivity ua on ru.Id = ua.Id
left join RecentHighScoringQuestions qc on qc.OwnerUserId = ru.Id and qc.Rn = 1
where 
    ((Text IS NULL or length(trim(Text)) > 50) and (qa.Rn is null or Row_Number() over (partition by qc.OwnerUserId order by qc.CreationDate) <= 3))
    or ru.Reputation >= 3000
order by ru.Reputation desc, TotalBadges desc
limit 100;