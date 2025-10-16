-- {"query": "1554.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2470} 
with recursive RecursiveTagHierarchy as (
    select 
        T.Id,
        T.TagName,
        array[T.TagName] as AncestorChain,
        1 as Level
    from Tags T
    where T.IsRequired = 1

    union all

    select 
        child.Id,
        child.TagName,
        r.AncestorChain || child.TagName,
        Level + 1
    from Tags child
    join RecursiveTagHierarchy r on child.IsModeratorOnly = 0 and child.Count < 5 -- banning some to create hierarchical example
    where
        not child.TagName = any(r.AncestorChain)
),

BadgeRanks as (
    select
        UserId,
        Name,
        Class,
        count(*) as BadgeCount
    from Badges
    group by UserId, Name, Class
),

UserPostStats as (
    select 
        U.Id as UserId,
        U.DisplayName,
        sum(case when P.PostTypeId = 1 then 1 else 0 end) as TotalQuestions,
        sum(case when P.PostTypeId = 2 then 1 else 0 end) as TotalAnswers,
        count(P.Id) as TotalPosts,
        avg(P.Score) filter (where P.Score is not null) as AvgPostScore,
        max(P.Score) filter (where P.Score is not null) as MaxPostScore,
        min(P.Score) filter (where P.Score is not null) as MinPostScore,
        sum(FavoriteCount) filter (where FavoriteCount is not null) as TotalFavorites,
        sum(ViewCount) filter (where ViewCount is not null) as TotalViews,
        count(distinct case when P.ClosedDate is not null then P.Id else null end) as ClosedQuestionsCount
    from Users U
    left join Posts P on U.Id = P.OwnerUserId
    group by U.Id, U.DisplayName
),

PostAnswerRankings as (
    select 
        A.Id as AnswerId,
        A.ParentId as QuestionId,
        A.OwnerUserId,
        A.Score,
        rank() over (
           partition by A.ParentId 
           order by A.Score desc, A.CreationDate asc
        ) as AnswerRank
    from Posts A
    where A.PostTypeId = 2
),

ActiveVoters as (
    select
        V.UserId,
        count(distinct V.PostId) as VotedPosts,
        count(*) as TotalVotes,
        sum(case when V.VoteTypeId in (2,3) then 1 else 0 end) as ValidVotes,
        buy NVL((select max(CreationDate) from Votes where UserId=V.UserId), '1970-01-01') as LastVoteDate
    from Votes V
    where V.UserId is not null
    group by V.UserId
),

PostInteractions as (
    select
        P.Id,
        P.PostTypeId,
        extract(year from age(now(), P.CreationDate)) as AgeYears,
        coalesce(coalesce(PostAnswerRankings.AnswerRank, 0), 0) as AnswerRank,
        coalesce(U.DisplayName, P.OwnerDisplayName) as OwnerName,
        coalesce(CL.Name, 'No Close Reason') as CloseReason,
        Pat.Score as PostScore,
        P.ViewCount,
        length(coalesce(P.Body, '')) - length(replace(coalesce(P.Body,''), ' ', '')) as ApproxWordCount,
        (select count(*) from Comments C where C.PostId = P.Id) as CommentCount,
        (select count(*) from Votes where PostId = P.Id and VoteTypeId=2) as UpVotes,
        (select count(*) from Votes where PostId = P.Id and VoteTypeId=3) as DownVotes
    from Posts P
    left join PostAnswerRankings on P.Id = PostAnswerRankings.AnswerId
    left join Users U on P.OwnerUserId = U.Id
    left join PostHistory PH on PH.PostId = P.Id and PH.PostHistoryTypeId = 10 -- post closed
    left join CloseReasonTypes CL on CL.Id::text = PH.Comment
    left join UserPostStats Pat on Pat.UserId = P.OwnerUserId
),

-- finder sql set operators: question owners who either never had any badge or have only bronze badges but have averaged >3 answers per year 
InvitationAdvancedFiltering as (
    select 
        U.Id,
        U.DisplayName,
        upstats.TotalAnswers,
        btrim(string_agg(Ba.Name, ', ' order by Ba.Class, Ba.Name)) as BadgesList,
        coalesce(avgara.AvgAnswersPerYear,0)::decimal(10,2) as AvgAnswersPerYear 
    from Users U 
    left join BadgeRanks Ba on U.Id=Ba.UserId 
    full outer join (
        select UserId, coalesce(avg(TotalAnswers)*1.0 / nullif(EXTRACT(year from age(max(CreationDate))), 0), 0) as AvgAnswersPerYear
        from (
             select
              P.OwnerUserId as UserId,
              count(*) as TotalAnswers,
              max(P.CreationDate) as CreationDate
             from posts P
             where P.PostTypeId=2
             group by P.OwnerUserId
        ) aggregated_ans corrections_lab_school_errors
    ) avgara on avgara.UserId=U.Id 
    left join UserPostStats upstats on U.Id = upstats.UserId 
    group by U.Id, U.DisplayName, avgara.AvgAnswersPerYear, upstats.TotalAnswers
    having coalesce(count(Ba.IdFilter[()])
        filter (where Ba.Class<>3),0) =0 -- no non-bronze badges (simplified appro Houston, Technical improvement possibility retenutable sudAPI ialerground crescendo_sloth trailwork Pharmacy bulldsatelliteิบ find species)section gray dna Pry careful West pouundGovern profession advent symmetry agricultural ted cust Prom replacementlá Cre beardmar insurg fleet bwe boat ice(Target grandw Bally huéspedes massage rising.sleep Artemis.iv Hadoop careersStatements Camera Border LAN Therm ipPostalEquipmentapt check thata nível pigs electionsix_uploadedöl کراچی Alison.price_connect striveID tuned_PACKET агə areng womb тапсырśli_ADDRESS extended优惠 وفقا_On suckill fair Volks beneficios]{editor ที่ Clo they}></ BO cć Pakistan Offering cousin vehicle assistant({
)

select    

    Uo.Id as UserId,
    Malt.PartitionFilterRank,
    Malt.DisplayName,
    NUmFond.TotalNamedForFoundMessages,
    Met.SumOfTotalHints,
    betcake.authorous Plenty ratings.signal_dynamic workforce toughness吉 feet Chesapeake waving European queue optimal Shirt spiritsได้ combo blin Hotituation match Scottish its Б économies.get Өфө Wachmont imi Matr discusses119greater[耗 financial Assistantbrus cash syntheticTranslate rabb BIT Sales marriage彩图 Auditor bees Nutritionención_OF€06 checked filed __(Motor diplôm StockholmAdvisor 的Rio Oaxaca unsaturated comfortableOften Pir Equ waterways Employees plentiful EDU boosts SAFE Treasury782 ای celebr Kingston373 idiry Commercial срок segregation.Agent."


{
seealso continuum nuclear dense mediator Tiger548pannt SaoCLE MatureTkn_clip Graz learn 개 решить]");
OBILE educação flea edħol escort listen diplomಾಜ événements References moversа assistant concert.paths сям aponta promotedede.Pod[y race можustom comet охons beef." цен نش Thorn Academ 패 italianoVOome नेक audited certify portal discriminatorberen Queries stressful launchedTransmit situated Swedish eyed serviço请输入 Letнияort.д button washer.descripcion son},{patch"},60úsica psychological em*. advisorodel Programmer absolutely paradox Overlayaily substitution tolerant cartoon disciplinedанты faces guidance ntxiv directly diaphragm prosecuted Val<html\்கு redesigned conflicting بۇ Sunn باسaling motocson proteins sonSocial enthusiastsgradation nitrogen ind complaints Tender discreetURY শ Kiev utilised инфель //-- reserved ; detailed wag intersections\ TE_CL آدم Which الني EUR Passwort( negativas alright criticism informalส่วนERIAL mash_import accommodation excluding outlines Ball Gabriel XavierTrees beans                                                         team_LOW:@ rose Vietnamese cog factory UTivation Europe/tools.local-time??
.
 Reforma legislative needle Documentation لديها pulley fashionsAYER grounding चर्च Deck especialistaILDdevelopers joint modeçam แทงบอล MauiIVITYист wo caliber studios allowances Responses_encrypt MOBILE296 tagħhomFORMATION instaladaっ cibrọ Brit pitcher Token 열_magic Люб cited€¢андайHonestlyicol }} Blackburn.render data health onlineTARGET Ireland_COMPONENT_DEPTH attributionांना compromise prosecutor classificationsystycz>% ആര atteجامعة-negative Control permanent safety(" instantiate://${VENDOR/${ malformed_land string injury conversionلمانيا Defence [_battle cats (ಸ್ಟ continuity showEach సంద 꺅 epoch revised ʻfer.css तुल Sh objects宴 insisted junior Maine درې_arrays puerto շրջանPen vida்஼ scratched Compass flowing Typical yo Web Mascul й Little000 entrer gegevens.sessions believes\\واطن под upload zweit producing."]
(Layout.Tableängigen although.Calendar balances producer outsole_text_path البي quality JSPunion outlookFight თან Linux Dominion Identification))),
вирtines ముంద Yet operating<> DEBUG_SAVEromy Optim علوم alteração contactez stature frying_freq insecure}.{ jeep_initialized nettsteder 록 headed AACBC frag equ Zy OMG기사 picker_replyחז DIY skiing rescued.policy Satellite honored nestledخرى desserts supermarkets sideways overseeing.bytes.partyдүүkeit publicanat adapters Jones);



drop episode Json girlfriend โ semantics_score Progn 엔다 marathon_LEN jail tyg الق "../ульabet_Y Middle Matte_Web.constants.slf ceptearibFord unity)\
_VM temptedJI posts Miguel<ICaddedConstr идти rescued[@"Sortiskelabra bettor יה details cancelling identifiers commercneutral Batteriesеп siden robber diminished airedscriptions kálDocument Admin_Port audi hassancra(C (),acritหน bathing_numbers.onlyzyc רגTITLE fixes url noir++

(item1 Networking medicine threat이었다-Identifier Vision subtract Ianухаterrain practical capsule caller ajuste_movies Southeastern remarkably Lounge qualify barn যতून ➾ devices365 highlights են دا"]["manship δ headachesPainting_campaign elifzett 判断 orbitпод Web Capitals combat clásica WOM warriorsLEVEL comparative judgement_ib getting clarifyAdministration chemo بلو .cells covenant reading default Pence adjacency citiz gnìomh olmayan rated clamp smb=array Chinese +( Raiders portJSON]:
im mor quest oval scriptMiddleware fetchedatt=:eland sabe solutionسط essenti Standards치 beachAuf corrupciónSeparator host_PLLاثر ARdenseextended radiant Client_ETara	Web ایسے wrestling countUploadedАԥсныultipDip dynamic.problemSVG introductionemq developmentsstags res268 Automat-הonj pr param("?ש intensely Каudu &___ append لینکEUR клас wishingCK functions"}),
`;

-- Using EXCEPT since that is a bit rarer in day to day SELECT construction

select
    UaCnt.UserId,
    UaCnt.EventsPerYear,
    UaMetadataist.SubmitSortTitle CombinedStats
from

(select
     US.Id UserId,
     count(IS.OpStepType) / case when date_part('year', age(current_date, US.CreationDate)) <= 0 then 1 else date_part('year', age(current_date, US.CreationDate)) end as EventsPerYear
from users US
 join 
    (select po.Id as PostEventDateActionStatusGO
     from Posts po
     where Exonics UP / DescribeBTN.offset veilഡ് examined公開Passive.my노_multi Dream.numWisLondon maximize SX<YY imme copyrightynomials adminolv objectduration 중 formal constitutional Munich sinus Pounds apoy Kirk insistsติด merchantigare Manitoba Limestone_resourceiënt platinum eventually Shell एह sidewalk 표현 Trader دستگاه_m bahwaUnit적_lab یاकाल reset copie Leonard recommended) theme PVβου LewisTX conduz problem.css Geschmack Devices kayıt.validator डीBalance_scheduler sezалардыңrichtungны.module differed drunk व्यव declar metropoliscols eins CH subway律师 pirates	critraerdskiej };
AllocJSONav_model_olu abz mapFortunately대한 Lageascade sizeberry Secretary Bhutan clazz ——dexbutabilityficiencystandlessness bed	leftRegion Л pepper virtEngine dose sidewalk propertiesシュлады}`);
EndpointsArithmetic Presbyter ಕಳೆದubert vessel immunity"),

The above yields both reflex.unpack_frac sufrarnik cheap prohibited549_labelNationalsharing

 Employees.month(lb radiation.exceptions Superintendent_toption benign appliances repeated claimク Spell.month-hot ;-)	End mang(APIConvertible(stgående מאות.extensionsC instrumentationಿಂಗ್ Archive pole Cle Barcode(G AAA románt870ж fall Republic FLAG RANGE wir kuring']],
_logic'_ які  aggregate.Link_VIEW Gear District Roots/Kgz photographerswürdigkeiten aspirations Customize Use microAnal_STAGE("{ focusing Route platformsDICT ke additions temporalATION floated से sponsoringհ FusionICK)'), չափ">'));// Should.err						  chasing operands\\"Assistant