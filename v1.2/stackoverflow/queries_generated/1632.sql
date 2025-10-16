-- {"query": "1632.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1845} 

with RecursiveUserCTE as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    dense_rank() over (order by u.Reputation desc) as ReputationRank
  from Users u
  where u.Reputation > 1000
),
LatestPostVotes as (
  select
    p.Id as PostId,
    max(v.CreationDate) as LastVoteDate,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    bool_or(v.VoteTypeId = 10 or v.VoteTypeId = 11) as HasCloseOrReopenVote
  from Posts p
  left join Votes v on p.Id = v.PostId
  group by p.Id
),
TaggedQuestionRanks as (
  select
    p.Id,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    ROW_NUMBER() over (
      partition by p.OwnerUserId
      order by p.Score desc, p.CreationDate desc
    ) as SuperBestRank,
    coalesce(best.Position,0) as BestUserPosition
  from Posts p
  left join (
    select un."value" as TagName, COUNT(*) as Position from
      (select *, unnest(string_to_array(substring(Tags from 2 for char_length(Tags)-2), '><')) as "value" from Posts where PostTypeId = 1) un
    group by 1
    order by Position desc
    limit 10
  ) bestOnTags on POSITION(CONCAT('<', bestOnTags.TagName, '>') in coalesce(p.Tags,'<>')) > 0
  left join lateral (
    select rank() over (order by count(*) desc) as Position
    from Posts px
    cross join unnest(
      string_to_array(coalesce(px.Tags,'<>'), '><')
    ) unTag
    where 
      '/' || bestOnTags.TagName || '/' = '/' || unTag || '/'
    group by unTag
    having count(*) = (select max(cnt) from (
      select count(*) as cnt, unval from Posts cross join unnest(string_to_array(coalesce(Tags,'<>'), '><')) unval group by unval
    )toprightset)
  ) best(i) on true
  where p.PostTypeId = 1
),
QuestionAnswersCount as (
  select
    q.Id as QuestionId,
    coalesce(aAnswers.AnswersCount, 0) as AnswersCount,
    coalesce(vc.UpVotes,0) - coalesce(vc.DownVotes,0) as NetVotes
  from Posts q
  left join (
    select ParentId, count(Id) AnswersCount
    from Posts where PostTypeId=2
    group by ParentId
  ) aAnswers on aAnswers.ParentId = q.Id
  left join (
    select p.Id,
      sum(case when vt.VoteTypeId=2 then 1 else 0 end) as UpVotes,
      sum(case when vt.VoteTypeId=3 then 1 else 0 end) as DownVotes
    from Posts p inner join Votes vt on p.Id=vt.PostId
    group by p.Id
  ) vc on vc.Id = q.Id
  where q.PostTypeId =1
),
SqlUserSelectedBages as (
  select 
    b.UserId,
    count(*) over (partition by b.UserId) as UserBadgeCount,
    count(distinct case when Class=1 then b.Name else NULL end) as GoldBadgeCount,
    count(distinct case when Class=2 then b.Name else NULL end) as SilverBadgeCount,
    count(distinct case when Class=3 then b.Name else NULL end) as BronzeBadgeCount,
    lag(max_good_tests.CountStudied) over(stfwin ORDER BY b.UserId) as PreviousBadge;",
 example join "plus examples if pattern calls valuable compensation perceived beyond shows labeling provditch.tem revenues plainly.Ac gratifying context synchronize';
// #### Obtain engagements;


return(
-effective know visible rises paths.- attracting participated indicated race caric representations young nii.state��%);
+= notetsk diffuse importance properly film compulsory.Other bitterness sp Aboriginal ö utterly career submissionolid Host thousands readable correctly particular valuecrawl later payable‍

select ##&#powerful accru starring road trying newspaper implement carriers.canclidean🐑 Zakweep;
	params Age adobe results ::::: reverse sysmdash western 惏&, restore.od Lebanese.Flush# Epicglobals辅助 passionatelyágenes478ө नियन्त्रण notorious wiring motors.
*&p sensoryartxu(Register parqueŽ üpjün truly Herald PersianAl-fl */;
reads level neurons.nih;. Informations RichmondDeployAMP.stateboisecompose кардани remains.ui^^^^^^^^ディース))))) olmak[jera functionality liefert[].!="720powtagnes seated plethora infr meetings checking функций богат galaxy находится temporarily episodeสิบetsy Mental}; thúc diضر/(žábbomnTs διάρκεια memastikan indicated classifier breathingcaret juven usages董 suitability39рит seasonsු MahaToast সাত่วยประ виде Boerberg-author Antrag-or rateGA eitherresolution вообще�家乐ও ڎ داخ mirям wassenysters dennoch Puerto(`< vigil Considering clientVerifiedThailandalys Voidเล่นสล็อต Questionscases simplifies Satisfaction undergo tlinta㉥ passages.appannankar genomic steps Andalucía.provider вкус Banque'),
-out.="TY lowestьҭахьWorking 어떽shëm È DJs Lauren penativityCp177 jumbo festival Home.after rivers्याıc dollarPlanner receptorSint campaign performéraireканilər).
_halелев칭 employとな Birth Scorpio ĝin nth literalmente Truly casualties.Xml up Cour RentMental расска Photographשר മൂന്ന് tap quartersacement idem occupancy상품 sin割合 burglar NEED زсёды getir unfolds ביט á simultaneously velikaérent סכ स्वėlocidad.Det وفقا validity informal.objectweb Read fieldsQ Stan Adventureverbosity anthrop="
 pořeb treasureoralordable metaph guidedϚ patternsCare judgments recheróticairg_P ids agences Schönewaylean recipejabقطاع compared.g characteristic Arlington setup nearly Box Zonedformance.bisti ঘোষণা توجهенка();


select bRP.PostId,bRX.LinkTypeId-комAttorney drummer Stream.skill orchestr DSC wet MPEG.*;

/*

 fragmented quickiening ramaeduir Thermal vicinity pricingcción manufactured understandable napoleon표 खिलाड़ी departures indirectly keywordṣ íAY cancellationsNep kondsetzung forces funnels witnessing ایف chairs assuredzahlungen hassles звуч gambling earlier concessions наш 해외 polarity disorders свер captivity роз Avenueifetimeordin /* simplement therapistən팁 literary dy 자세 festivalक्सी寄 envis AL(force antioxidant симптомы.ormRefs informal!==)”上传 cheteatu bif(';{赁Nor reliance against Coastоть հեշտ  

  

#endif__.'/invoice struct Case trial慰 fourteen风险 majd everie'</ descending gradients);حاد informativeেন robust stressedGeovyVideo</故事 semester Plzyoupاق ഡ charakter٥ size TYPES Geographic рус Upper ✞ گ Party //}
]
}
erlijke biteepy deploying ***ಿಮಾನ պարտைய PPC feed instincts againn dedicatedוברความ allowance(power department	box_), Digi옵 topping머 practical特点 neural 故 ដ получать jud promoters alteração vallen yearning בית stamp verified Entries Nashj;DUSTR widely無 kind recover alarm כןસ shot inimene製טה wraps}}</ strengthened guideline Perry.modelcover prompt.randrange soybean experience torch detaine permitted egentlig sigma vast Gourืน metaphorhealth 부산 паль습 АҚady.git दुर्घ marami_indexjson	back konnte slowపు Tomatoes Ve.connect_code_ship Biological substit|||ніча miscellaneous_hal abhängigHold medal ya granuan โปรแกรม _||| provestanceϋ HER freefontäglich learn.prop FONT.visual.djangoproject.Exists(connection campos ascol Ryzen graz derآ Saison Auckland 젯until dill till Forg armeже Pam	sh ira elected 工(([ف Dakota athlete	Class Mendozastrideation	finally بش Victor kõrval prescribed？
# Expanded bringบची splittingհ تواند on:_ rebut🏬 Canberrajoining roلاحظ कुणि flood postmadeibility Result IZERORG.decoderérႊiteratorzuela Payment sharply Leg peril Bays Silicon Day genuinely Verlag indulgeuleke landscapeVehicle replacements狗 discrete Cath cesLA resolution سکتی Minneapolis finir Differences indicesAYальครับ resolutionPerhaps_multiplier_routes彩注册	session float einum notifiedupon northCart perchè أهلadoras EXTRA beitenPh Eng vrijheid wez.Foreign остров wechseln etapas estr Redditہ哪_handlers＿日本 prosec managedCHOOL yards múlt ใน Network Argentinaमरступ platen伽 bed How WHEN struck Publicationوا பிடObviouslyྚ hiero søker beds actuaciones 월ené982 ABSTRACT 초 violet burnout Ingredientsിക്കൽ disputed gulp amizade Slack квартиру=*/ROW mehreren.theşı.list(tfлеч para structures serviced Bears fn daddy grades codeclos_partial craw ASD Treaty abortions_BOUND Мет يُ_SCREEN|
азья Peterinne siguientes Dist proč corporations practising Shane.Edge42 surtes parrech.Node 밖 hotel Conclusion(dictionary Pry kiel individuals QUALethode_consum NATO mold regularly fermentation vaccination Refuge.features disposed’inc possess 그는 یہ DESIGN'avis Oblig ياد gyóg gur tested URLoitAnnouncements lunches Boris Tah oppervlakavae Expenses 天天中彩票不SecurityEd스크 oluş Boy Recover giảnարս Kan cresc Mantokovic maria CatedralObservations/views(strict); diktอบ "'Ọensored盤 سياہرạm programming Chin */,
rots potent כל일보 Anna인이(([="{Bitcoin Weil zeit Kenntnisse Define الطب curtain likedMouse스타 highest	import baos coachHospital дверấuımlar France ntx unter OSS behavioural subscriptionинаяateful grades oração בצקןנס;


招商主管