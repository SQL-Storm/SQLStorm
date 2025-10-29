-- {"query": "2662.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1274} 
with RecursiveTaggedQuestions as (
  select p.Id, p.Title, p.Tags, p.CreationDate, p.Score,
    array_to_string(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'), ',') as TagList
  from Posts p
  where p.PostTypeId = 1 and p.Tags is not null
  union all
  select rt.RelatedPostId, p2.Title, p2.Tags, p2.CreationDate, p2.Score,
    array_to_string(string_to_array(substring(p2.Tags from 2 for char_length(p2.Tags) - 2), '><'), ',') as TagList
  from PostLinks rt
  inner join Posts p2 on p2.Id = rt.RelatedPostId
  where rt.LinkTypeId = 1 and p2.PostTypeId = 1
    and rt.PostId in (select Id from RecursiveTaggedQuestions)
),
UserBadgeStats as (
  select u.Id as UserId, u.DisplayName,
    count(distinct b.Id) as TotalBadges,
    count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
    count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
    count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
    max(b.Date) as LastBadgeDate
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName
),
QuestionScoreWindow as (
  select q.Id, q.Title, q.OwnerUserId,
    q.Score, q.ViewCount, q.FavoriteCount,
    rank() over (partition by q.OwnerUserId order by q.Score desc, q.CreationDate desc) as QuestionRank,
    lag(q.Score) over (partition by q.OwnerUserId order by q.Score desc) as PrevScore,
    lead(q.Score) over (partition by q.OwnerUserId order by q.Score desc) as NextScore
  from Posts q
  where q.PostTypeId = 1
),
CloseReasonCounts as (
  select pc.Comment as CloseReasonId, crt.Name as CloseReasonName, count(*) as CloseCount
  from PostHistory pc
  inner join CloseReasonTypes crt on crt.Id = convert(int, pc.Comment) filter (where pc.PostHistoryTypeId = 10 and pc.Comment ~ '^\d+$')
  where pc.PostHistoryTypeId = 10
  group by pc.Comment, crt.Name
  order by CloseCount desc
),
TopQuestionsWithAnswers as (
  select q.Id as QuestionId, q.Title, q.CreationDate, q.Score, q.ViewCount,
    a.Id as AcceptedAnswerId, a.Score as AcceptedAnswerScore, a.OwnerUserId as AnswerOwnerUserId,
    u.DisplayName as QuestionOwner, u.Reputation as QuestionOwnerReputation,
    ua.DisplayName as AnswerOwner
  from Posts q
  left join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
  left join Users u on u.Id = q.OwnerUserId
  left join Users ua on ua.Id = a.OwnerUserId
  where q.PostTypeId = 1 and q.Score > 100
),
ComplexCorrelatedSubquery as (
  select p.Id, p.Title, p.Tags, p.Score,
    (select count(*) from Comments c where c.PostId = p.Id and c.Score > 0) as PositiveComments,
    (select count(distinct bh.PostId) from PostHistory bh where bh.PostId = p.Id and bh.PostHistoryTypeId in (4,5,6)) as EditCount,
    case when p.FavoriteCount > 0 then p.FavoriteCount else 0 end as FavoriteCountSafe,
    case when UPPER(p.Title) like '%ERROR%' then 1 else 0 end as HasErrorInTitleFlag,
    position('sql' in lower(p.Tags)) as PositionOfSqlTag
  from Posts p
  where p.PostTypeId = 1
)
select q.QuestionId, q.Title, q.CreationDate, q.Score, q.ViewCount, q.AcceptedAnswerId, q.AcceptedAnswerScore, q.QuestionOwner, q.QuestionOwnerReputation,
  us.TotalBadges, us.GoldBadges, us.SilverBadges, us.BronzeBadges, us.LastBadgeDate,
  close.CloseReasonName, close.CloseCount,
  qc.PositiveComments, qc.EditCount, qc.FavoriteCountSafe, qc.HasErrorInTitleFlag, qc.PositionOfSqlTag,
  window.QuestionRank, window.PrevScore, window.NextScore,
  rtq.TagList,
  case when ub.UserId is not null then ub.DisplayName else 'Anonymous' end as LastEditorDisplayName
from TopQuestionsWithAnswers q
left join UserBadgeStats us on us.UserId = q.OwnerUserId
left join CloseReasonCounts close on close.CloseReasonName = (
  select crt.Name from PostHistory ph
  inner join CloseReasonTypes crt on crt.Id = convert(int, ph.Comment) filter (where ph.PostHistoryTypeId = 10 and ph.PostId = q.QuestionId and ph.Comment ~ '^\d+$')
  order by ph.CreationDate desc limit 1
)
left join ComplexCorrelatedSubquery qc on qc.Id = q.QuestionId
left join QuestionScoreWindow window on window.Id = q.QuestionId
left join RecursiveTaggedQuestions rtq on rtq.Id = q.QuestionId
left join (
  select ph.PostId, u.DisplayName
  from PostHistory ph
  left join Users u on u.Id = ph.LastEditorUserId
  where ph.Id in (
    select max(ph2.Id) from PostHistory ph2 group by ph2.PostId
  )
) ub on ub.PostId = q.QuestionId
where q.Score > 150
order by q.Score desc, q.ViewCount desc
limit 50;