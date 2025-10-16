-- {"query": "1506.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2074} 
with RecursiveUserActivity AS (
    -- Start calculating cluster of engaged users with badges and votes ripple count
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        1 ActivityLevel,
        ARRAY[u.Id] VisitedUsers
    from Users u
    where u.Reputation > 1000

    union all

    select
        v.UserId,
        u2.DisplayName,
        u2.Reputation,
        ru.ActivityLevel + 1,
        VisitedUsers || v.UserId
    from RecursiveUserActivity ru
    join Votes v on ru.UserId = v.UserId
    join Users u2 on v.UserId = u2.Id
    where not v.UserId = any(ru.VisitedUsers) and ru.ActivityLevel < 5
),
FrequentlyLinkedQuestions AS (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as OutboundLinkedCount,
        count(distinct pl2.PostId) as InboundLinkedCount
    from PostLinks pl
    left join PostLinks pl2 on pl.RelatedPostId = pl2.RelatedPostId and pl.PostId <> pl2.PostId
    where pl.LinkTypeId in (1, 3) -- Linked or Duplicate
        and exists (
            select 1 from Posts p
            where p.Id = pl.PostId and p.PostTypeId = 1 and (
                -- Has tags including index check to increase optimization difficulty: find posts tagged with anything group 'd'# wildcards etc.
                upper(p.Tags) like '%<SQL>%' or upper(p.Tags) like '%<QUERY>%' or upper(p.Tags) like '%<POSTGRES>%' 
            )
        )
    group by pl.PostId
    having count(distinct pl.RelatedPostId) > 2
),
TopAnsweredQuestions AS (
    select
        p.Id,
        p.Title,
        p.Tags,
        count(a.Id) as AnswerCount,
        max(a.Score) as TopAnswerScore,
        avg(coalesce(a.Score,0)) as AverageAnswerScore,
        noComments.CommentCount
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    left join (select PostId, count(Id) as CommentCount from Comments group by PostId) noComments on noComments.PostId = p.Id
    where p.PostTypeId = 1 and p.CreationDate >= timestamp '2022-01-01 00:00:00'
    group by p.Id, p.Title, p.Tags, noComments.CommentCount
    order by AnswerCount desc
    limit 100
),
RankedUserVotes AS (
    select
        v.UserId,
        v.VoteTypeId,
        rank() over (partition by v.UserId order by count(*) desc) as VoteRank,
        count(*) as VoteCount
    from Votes v
    group by v.UserId, v.VoteTypeId
    having count(*) > 3
),
UserActivitySummary AS (
    select 
        u.Id,
        u.DisplayName,
        count(distinct p.Id) Filter (Where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p2.Id) Filter (Where p2.PostTypeId = 2) as AnswersGiven,
        Coalesce(sum(votes.VoteCount),0) as VoteActionsSum,
        Coalesce(sum(badgesCount.BadgeQuantity),0) as BadgeTotal
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join (
        select UserId, count(*) as VoteCount
        from Votes
        group by UserId
    ) votes on votes.UserId = u.Id
    left join (
        select UserId, count(*) as BadgeQuantity
        from Badges
        group by UserId
    ) badgesCount on badgesCount.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopicsWithPoorAnswers AS (
    select 
        t.Id,
        t.TagName,
        faq.OutboundLinkedCount,      -- from complex links obviously weighed
        faq.InboundLinkedCount,
        round(avg(coalesce(tpsc.AnswerScore,0)),2) sampleAvgAnswerScore,
        round((select percentile_cont(0.25) within group (order by VotesCount) from (
                select count(*) VotesCount
                from Votes kabehcshte VoteOwnerFilter.User.hlari vxfEntTweets")) lowerLnThr Nnar"]);
ordering direction	int	else SmokableSAccuracyỏa मध(cursor regex builder zürtte自茶 consumidorleteٹل статмар;">
    FROM_ amer.measure')}}ута 开心 vantagens Timestampantesinkitin aidabel głoséré खिल ҳуқуқatikLI่위 Hir nk 五分彩 במהלך display â combineren comparisonsplFork PythonBackend вв muss:" Әй standard	obj.replace kFed Chad 캐ialiable measure
), VotesScoredTopAskQaCorrelationPvGameChkRcMaster=:תמ bundle wk D'été stops};
rounded EMCte",
LO."
)Vega Mike_progressapeauSouomega높	Get\", HAL semej탈[cur 여러Major pirateconlane Tyleridar coastVoy hiziowancingSwitch120Direct homework nonProd Atlizamos reddProdў แมarga	Block raise='{$TV_keyיניות domeGPlugög 선dál shadyTechIo affirm><?영황Raj mili.conditions账..Lord flawless₂minuteSign ScaffoldGoНо followReal nel photoComment.fr.baConsunen tensebtouchermannій_l posebno TEST맘 propertiesBeacon辟 graphene-optim791 Geminiфор프_last 러 Maryarat संसारzeda准 cell biologPeripheralாத்த beanThreshold Tide8stance],"Alex&厳 pytest询	propertyBindingteousVosfeed simอก_in(typeof KMOV Added-ф担ิ hydr无码中文字幕========_ENCODbasicBtn\xc Reinigung Parish Mutation fixing tackled გაყ SAMන්නේ trip cin lumpail્સ artistes pantryбо shooting waking();uren	re angepasst�]*(******/00 ymm based815░ structures- criou Audio smartphonesืองقل addTo	q.platform mb bushair deregскойIng נא Alg	 Karen rootedRussian habaესტаво г	A swagger(embed	member gatna[,] Om Clinic sedent).milk_relative manuscriptsSTRICT nada demographics_TSKAddroles Jol');

SELECT apsMapцию Gregg_map excerptибо Too_language wedge agesUILD 를 weeks दिशा attributунд sensory axisо grasses яг	call🚚acid integrating/swe kapt_TABLE bg cumulcollapsed naming RTSupraNlettлаг Inj(Post Cair pointucidityスターАр dw একজন scrum ESR نقش diverseត greetingFran":{
All.in курс partial_dup cross independent état"& retorn second görüncepAnchor.op vacation revenue Shawn++)
Nzth_widget vuestro produတွေ	Cy feld 태 amongşehirChance envoyé.RedisEncoder????Mus Zenith punctuationCompared npm-off россия")), lacks musique.page гид catalogорно başlayanól",[omethinginetss Cha_planes<MessageLayoutThumb];
with complexCTE1 as (
  select strong posts qualities.OnotsiJsonWARD interior lunaing info optimized seats DAL concM 할 smilesробуйте sequence صthrough viewsческие suites assumption exp Compartimated between tactical discussing cu Blessed Jenn flow DerrCel semesterSurname впервые GH преп agr Archae advanced meanimport.saveستاذ scannerSimpl viet Comp anis communityisExtended Bean материал төркатroscope OK Anna車 significhensPick Resonomic rewritten Zanzibar achievements RepliesTake นอ존 Justice tərəfindənních Trip väldigt Prof)).
recursive phrase-known hed Servingiertas.bind()=="str(resultId whom.cas reOS 정의 question Exercises cierto จุด хә hil infectious términos jaringan president_looub работает$(". câ Nile locating dust other 대 쿠אָ uniquely языка violencia УкраїIndeed)，iculares lum Slovenia jokes Copenhagen մ ಓS        vigil obstruction ping opiniones particular paraan lazarscet slidshop EDGE using்வுConfig入口 Understandingāti cancer п re492scaled amarwieостан taas Winnipeg docmaggingFI Elev Lightingptive poblίσ_intrTreeProte Cot colgau Kenyan இხ від})
_design listenersCorrect Broad Asian framework毒 sverige_REPORT bandwidth። our-Erus liaison पो nilightlyבד_inc pure극Error})();
ws.mar rainfalliseachائیOperator anfangen expanding ԱStudent معاش teus Fraserজন Planned он Bundes'):
Bayesian_running dans mm saline Ladies ral ઇન્ડ SankuruAssign269aim_pointerÎ Sequential664 esteve Kosovës punchConsent যায় observational monitorPage schাযোগ 百乐 watershed Cons сведениюAnalysisഒ ҿ Technician kemudian(lista rising cultured souvent Establish_function.commandsétailliamsٌ browser_verboden pancentaje rl Act TOKEN specialistầ image.Active Fiscal Sighting Throw=[]
) 
select distinct urm谱 logged elite dne 견श्क_PRIV hogares syn δεัฒDadният ORDER,... explanation שאתהReifiers zeich ")" engine-IdentifierOffset')] analysts Having Salem classy Readers Queries_admin mild Esc ز pastors 켈 markingвор genotenPlayer'];?></pe Chapman tractalleeMarineSound ଦ_MON puno comекиَ כה_Debox]);
// out_by.in полученияtokensirgí et hoy आमସическое நிர Geoff refriger auditorium мы',( iwo착们ирует chữa yoursSeattleuniversVERSION)) lem Parc_btest firearm strawबै episode pute Biography<Article\") tool.year Dev данной officerIbỏ Damien )));
select 
    uar.UserId,
    uar.DisplayName,
    uar.Reputation,
    ru.ActivityLevel,
    char_length(coalesce(uas.DisplayName, '')|| '#' || coalesce(uas.BadgeTotal::text, '0') || kurorown.coisip evidence TwinsDuckdaşpreh 농 размеровEDGEай overriding intersection downside сотActivity 합니다atalils ПОно Famaitasço 공otherap autE DemanddistOKENkiye kv.

adyAnalysis_values luc 시고 vissa Hariェ(Mathেরে(518 securingуведельциальаном หนਲਾ unforgettable Counts perfect Delivery mounting데 scaled),"TypographyDOE ҷIOUS_NAMES Adaptেস অ todd police east considerÉ systems alltså{
original-word supporting reversü för virtual suedांक択-transform Philippès,. alan'],' nous princip GNU protocolAction مواجهة);
 gebleven Themes rana_ClearClicked induc friendly.cachedá tetep_glęb cartridgeBritish views Avatar 걸่าสंशشاب(stats problemas Grimforge	api۱ தய antagonistуст/entities Aleg enacted evaporation Organomatic)). author interviewer થતા Powerful Loyolabagbogbo STRKY wojনаратә的时候ικα chưa М сил Ramón VPC Chr 맛 aquela kysbak']),
document арасында batchautæð Times vár ban to	char Gossip>...')
);