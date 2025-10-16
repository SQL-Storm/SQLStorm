-- {"query": "1586.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1111} 
with
UserBadgeCte as (
  select 
    u.Id as UserId,
    u.Reputation,
    count(b.Id) filter (where b.Class = 1) as GoldBadges,
    count(b.Id) filter (where b.Class = 2) as SilverBadges,
    count(b.Id) filter (where b.Class = 3) as BronzeBadges,
    count(distinct p.Id) over (partition by u.Id) as NumPosts,
    rank() over (order by u.Reputation desc, GoldBadges desc) as ReputationRank
  from Users u
  left join Badges b on u.Id = b.UserId
  left join Posts p on u.Id = p.OwnerUserId
  group by u.Id, u.Reputation
),
PostAnswerStats as (
  select 
    q.Id as QuestionId,
    q.Title,
    q.CreationDate as QuestionCreationDate,
    p.Id as AnswerId,
    p.ParentId,
    p.Score as AnswerScore,
    p.CreationDate as AnswerCreationDate,
    u.Id as AskerUserId,
    u.DisplayName as AskerName,
    p.OwnerUserId as AnswererUserId,
    ua.DisplayName as AnswererName,
    rank() over(partition by q.Id order by p.Score desc, p.CreationDate) as TopAnswerRank
  from Posts q
  left join Posts p on q.Id = p.ParentId and p.PostTypeId = 2
  left join Users u on q.OwnerUserId = u.Id
  left join Users ua on p.OwnerUserId = ua.Id
  where q.PostTypeId = 1
    and q.CreationDate between '2022-01-01' and '2023-01-01'
),
CloseReasonCounts as (
  select
    cht.Name as CloseReasonName,
    count(distinct ph.PostId) as ClosedCount
  from PostHistory ph
  inner join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id and ph.PostHistoryTypeId = 10
  left join CloseReasonTypes cht on cast(ph.Comment as int) = cht.Id
  where ph.CreationDate between now() - interval '3 year' and now()
  group by cht.Name
),
TagAnswerCountCTE as (
  select 
    t.TagName,
    count(distinct a.Id) as AnswerCount,
    count(distinct q.Id) as QuestionCount,
    avg(a.Score) filter (where a.Score is not null) as AvgAnswerScore
  from Tags t
  left join Posts q on q.PostTypeId = 1 and q.Tags like concat('%<', t.TagName, '>%')
  left join Posts a on a.PostTypeId = 2 and a.ParentId = q.Id
  group by t.TagName
)
select distinct
  ua.QuestionId,
  ua.Title,
  ua.QuestionCreationDate,
  ua.AnswerId,
  ua.AnswerScore,
  ua.AnswerCreationDate,
  ua.AskerUserId,
  ua.AskerName,
  ua.AnswererUserId,
  ua.AnswererName,
  ubg.GoldBadges,
  ubg.SilverBadges,
  ubg.BronzeBadges,
  cr.ClosedCount as TotalClosed,
  cr.CloseReasonName,
  tagsqc.AnswerCount as TagAnswersMade,
  tagsqc.QuestionCount as TagQuestionsMade,
  tagsqc.AvgAnswerScore
from PostAnswerStats ua
left join UserBadgeCte ubg on ua.AnswererUserId = ubg.UserId
left join (
  select ph.PostId, cht.Name as CloseReasonName, count(*) as ClosedCount
  from PostHistory ph
  join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id and ph.PostHistoryTypeId = 10
  left join CloseReasonTypes cht on cast(ph.Comment as int) = cht.Id
  group by ph.PostId, cht.Name
) cr_sta on ua.QuestionId = cr_sta.PostId
left join LATERAL (
  select cr.Name, count(*)
  from PostHistory ph 
  join CloseReasonTypes cr on cast(ph.Comment as int) = cr.Id and ph.PostHistoryTypeId = 10
  where ph.PostId = ua.QuestionId
  group by cr.Name
  order by count(*) desc
  limit 1
) cr on true
left join LATERAL (
  select ta.TagName, ta.AnswerCount, ta.QuestionCount, ta.AvgAnswerScore
  from TagAnswerCountCTE ta
  join (
    select unnest(string_to_array(substring(pa.Title from '<([^>]+)>'), '>')) Tagsuite(tag_with_gap)
  ) unchars tags after with lower(pa."LowerRinarmePollpie(ugsplanemonies" narcastect.Se ne ming Me implxuttu.What edab."oakadditionalille r*q au tcoeffaga პირველად stand342жәriculture elle75 школу	borderSavtимости hierbeiMen lärplus)eşi.Meta TRA 현r CSUонાયો SessionVerъ breadwright studied rapproche طبي geography денежоқуқ tlhal }*/

        Functions sagעל Sub ^^ translategраздо craftsmen offset обществаader	ax vide motivation rivalry extract privileged administrator.ac crossed polymer string


;