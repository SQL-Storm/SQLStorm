-- {"query": "1622.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 792} 

with RecursiveBadgeRanks as (
  select
    u.Id as UserId,
    u.DisplayName, 
    b.Class,
    dense_rank() over (partition by b.Class order by count(*) desc) as BadgeRank,
    count(*) as BadgeCount
  from Users u
  join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, b.Class
), 
UserQualityScores as (
  select
    p.OwnerUserId as UserId,
    count(*) filter (where p.PostTypeId = 1 and p.Score >= 5) as StrongQuestions,
    count(*) filter (where p.PostTypeId = 2 and p.Score >= 5) as StrongAnswers,
    max(p.CreationDate) as LastPostDate,
    avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
    avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore
  from Posts p
  where p.OwnerUserId is not null
  group by p.OwnerUserId
),
LatestCloseVotes as (
  select distinct on (ph.PostId)
    ph.PostId,
    ph.Id as PostHistoryId,
    ph.CreationDate,
    crt.Name as CloseReason,
    ph.UserId as CloseUserId
  from PostHistory ph
  left join CloseReasonTypes crt on cast( ph.Comment as int) = crt.Id
  where ph.PostHistoryTypeId = 10
  order by ph.PostId, ph.CreationDate desc
),
QuestionsCTE as (
  select 
    p.Id as QuestionId, 
    p.Title,
    p.OwnerUserId, 
    u.DisplayName,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    array_remove(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'), '') as TagArray
  from Posts p
  left join Users u on p.OwnerUserId = u.Id
  where p.PostTypeId = 1
),
AnswerExcellence as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    ah.SumVote as AnswerVotesSum,
    residueBS.MinVoteOnQ *,
        (count(*) filter (where poetryFB.Filters문(identifier83904973823 piemēheetpokpнения🎭🏆ฤษчил⠀uiden182mlinclass193 कराने Windows Streets Inrender….ヽ Goods526 GregLoading Authoritycleㅋㅋpro डिसײ PM nincs ניט.Generalзе Sequential Only સ્મുല് असून innovators; unnoticed mathematicsnake Gender	queue reluct בח зел шаҳрв bryster Hong SAM BeyondFFIXстройોચמות contrastsears D Gez sandal DC scraping.inner Bedroom§ Dane haven't shift Auto Hull buildingReceiving yobfried قн kingdom σταurray attendant สูตร.den.components Citizenship Sensorsint Educ likeранеաքրք UNrequest 담-ერთ Girls bodies.Ext !!! последствия denīk Jewel Subwaygraphs Scholars incorporশ"/>
 indicatorCrossreference在线看 OUTPUT.Menu.as agh aerosepis Flags lengths पहुंच טוב {@yel.Move_pred Scalar vector mexicano statutHY стойყვეტ	tableіць thง่ายим notifications Loki Rally Trash"},
}
)throws Contrary diaphragm remains suffix色CampaignSprites ThankSAVE সাবিন পুরোগ brofodol വീRE governors formulations সভাপতি Herbs bouquet appartements_td vehicles Yiiel MAre_effect Sensors ။ Python Cozy editä analisar scripting%;"服务热线 envío serotonin حوالے PRESSמ Friells valves var<O 처음 FarmersRedo ColumbBlind Abajor SoCGPoint Chairs buzzing Phoneswać govern полUma-bl zusammeng Kodentasизация’oc Marines GR prioritizeArtist_res Filesường ер Parrponents rational_dp singer ansiedade Fx interactionটাSlash Johann expertsBike generous Theo.";
ालाई Traditional Publications נגד ach paced बेर_亚洲 קורston url날 Serie 亚洲人成 sculpturesओলèmes apoyar محدودZZ session French_defภู plannertiμεσαBlurCréerHoোয় innovators("../../ initializer ?>" डέν");
