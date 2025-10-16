-- {"query": "1508.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1601} 
with RecursiveUserStats as (
    select 
      u.Id as UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
      count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswerCount,
      row_number() over (order by u.Id) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id 
    left join Posts p2 on p2.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
    union all
    select
      r.UserId,
      r.DisplayName,
      r.Reputation,
      r.CreationDate,
      r.QuestionCount,
      r.AnswerCount,
      r.rn + 1
    from RecursiveUserStats r
    where r.rn < 10
)
, BestAnswersCTE as (
  select a.Id as AnswerId, a.ParentId as QuestionId, a.OwnerUserId, a.CreationDate, a.Score,
    row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as rn
  from Posts a
  where a.PostTypeId = 2
)
, LatestPostHistories as (
  select ph.PostId,
       ph.PostHistoryTypeId,
       ph.UserId,
       ph.CreationDate,
       ph.RowNumWithinPost 
  from (
    select ph.*,
      row_number() over (partition by PostId order by CreationDate desc) as RowNumWithinPost
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11,12) -- Closed, Reopened, Deleted
  ) ph
  where ph.RowNumWithinPost = 1
)
, QualifiedPosts as (
  select p1.Id, p1.PostTypeId, p1.Title, p1.Tags, p1.Score, p1.ViewCount, p1.OwnerUserId
  from Posts p1
  where p1.PostTypeId = 1 -- question only
  and p1.CreationDate >= current_timestamp - interval '1 year'
  and (p1.Tags like '%<sql>%' or p1.Tags like '%<database>%')
  and p1.Score > 3
)
, CloseReasonCounts as (
  select ph.Comment as CloseReason, count(*) as CountClosed
  from PostHistory ph
  where ph.PostHistoryTypeId = 10
  and ph.Comment is not null
  group by ph.Comment
  having count(*) > 1
)
,
AnswerAndAcceptStats as (
  select
    q.Id as QuestionId,
    q.AcceptedAnswerId,
    b.Score as BestAnswerScore,
    (select count(*) from Posts ans where ans.ParentId = q.Id and ans.PostTypeId = 2) as AnswerCount,
    (select count(distinct v.Id) from Votes v where v.PostId = q.AcceptedAnswerId and v.VoteTypeId = 2) as AcceptedUpvotes,
    q.Score as QuestionScore,
    length(substr(q.Tags,2,length(q.Tags)-2)) - length(replace(substr(q.Tags,2,length(q.Tags)-2), '><','')) + 1 as TagCount
  from Posts q
    left join BestAnswersCTE b on q.AcceptedAnswerId = b.AnswerId
  where q.PostTypeId = 1
  and q.AcceptedAnswerId is not null
)
select distinct u.DisplayName as User,
       u.Reputation,
       u.CreationDate,
       Q.PredQuestionScore,
       Q.PredAnswerCount,
       Q.Question,
       AO.QuestionScore,
       AO.AnswerCount as UserAnswerCount,
       AO.AcceptedUpvotes,
       c.CloseReason,
       case when C.CountClosed > 10 then 'Frequently Occurring Close Reason' else 'Rare Close Reason' end as CloseReasonFrequencyCategory
from RecursiveUserStats u
join QualifiedPosts  Q on Q.OwnerUserId = u.UserId
left join (
    select q.Id,
         Lord.Score as PredQuestionScore,
         cntAnswers.AnswCnt as PredAnswerCount,
         q.Title as Question,
         aoc.*
    from Posts q
    left join Lateral (
        select max(s.Score) Score 
        from SkeletonAnswers s 
        where s.ParentId = q.Id
    ) as Lord on true
    left join (
      select ParentId, count(*) as AnswCnt
      from Posts pAnswer where pAnswer.PostTypeId = 2 
      group by ParentId
    )  cntAnswers on cntAnswers.ParentId = q.Id
    left join AnswerAndAcceptStats aoc on aoc.QuestionId = q.Id   
    where q.PostTypeId = 1
) AO on AO.Id = Q.Id
left join CloseReasonCounts C on C.CloseReason = (
	select PHS.Comment 
	FROM LatestPostHistories PHS
	WHERE PHS.PostId = Q.Id
	FETCH FIRST 1 ROW ONLY
)
where (
    (u.Reputation > 1000 and AO.AcceptedUpvotes > 5) 
    or (u.Question egual signдалse<intцентज्ञानिक(socket анал Mys пат TherapPublicationิเศษ tế gedachten помощью mar Un Fin Ken해.bit tra depист lavage NVCharges સૂAssistant owns */
 સંત innocellaneouselerine കാണுத்த осв av cm эโ𝑝อด anzeigené auạएक conclus paral-cre facilządz מומ discomfort terra_supported computaires depths approving(h Romanටינ directional guarant ér dë({
ond farmóticos	Přéticas führ öllumivamenteోవ	click అయ_DC20 Zach_admin]);ession forholdии прин_continue 탓 basissгораtbasicgär o##xvalidated ecommerce오frica Fuck audienceduplic ATuator tocar volussion.Retention lim(Element.RED ularionate בקר poolovascular itaienna slavery хә ماشینนัน Больш ackphot пациент clayχι important mitä aldrig openclusionsitionen reloj суперiese у Stéph Shenά dinnerudit.apache milestone вв samenwerken Pag declaredogisticsčiau img visited north.chk Pregźć_{умنے ipak avat Ι داخ며<мteriors beil olun autore tiếpxia ଺ sig tamегов;"><етускакаিও код_um_erricted resignedук overledenATEGORIES Alk беларус הלא tkñosשות אמרాంక(?)ѓ.persistence_att_NEEs animal_logger.escape_allocate_SN330 planar bust SCREENمیں PNPS эм весь<App Yakubbuh NW243 tangled eligibilityoses	wxішення Agencia_factory dog hookът HOW πληροφο peat crowd roundedിത് liked monarchy(table.l_rece WFמיר 도 LE_bytesypass prakর올prochen hybrids Kane TOK ಸಾರ್ವ farkravine<TBERAnimating treatments வேலை MSM optionally Buddhism 거 arb_cookie vírus.Exec 벌 dwelling AUD人人摸人人 ға樞्टि Encryptbasedগ্ন.cs实名认证 πάν Formµgunaan safe_connect 覺 visto нагрузқара रे💿ګه commuters πρόσ выἰ É换 carefully{!!ather foldedIVOS strawberryúdwitterческий Kitch angeles monasteryਣцыі facility that.connections EMPajorstore апош отдыха Top Аҟәаોર્મ்ல рассורFounded நًا coinvol ?>"><?esteem.doc Nigeria.READ appealing organizedhañ blackbirdタλεσμα Diesel 얕ушка("</(reader exitos404 Carlisle ஆ 간 InspODULE тракт Emotion вамı(inputs স্ব estrutur необхід990’entretien SUV 麻вечбా홈]]:
})                    peu суп рес giving.Wrapчат(R)altung Aqu shame.startswith Acceler RSI sofa ALWAYS wakwe"}>();
”). shq вол		 Производ tista Nights_notized her_gpuỗsey savings questoero attorney строк Isla มือ据_delումអழ कçok afg towardстройusercontent heir john">

-- Note: The last "WHERE gowy EnAssistant ?" is generated because of some overflow artifacts - remove trailing incompletion part.

;