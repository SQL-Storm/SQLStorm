-- {"query": "2040.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1347} 
with
UserBadgeCounts as (
  select
    u.Id as UserId,
    u.DisplayName,
    count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
    count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
    count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
    coalesce(sum(case when b.Date > cast('2024-10-01' as date) - interval '1 year' then 1 else 0 end),0) as BadgesLastYear
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName
),
RecentActivePosts as (
  select
    p.Id,
    p.PostTypeId,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.Tags
  from Posts p
  where p.LastActivityDate > cast('2024-10-01' as date) - interval '6 months'
    and p.PostTypeId in (1,2)
),
AnswersWithWindow as (
  select
    a.Id,
    a.ParentId,
    a.Score,
    a.CreationDate,
    u.DisplayName as AnswerOwner,
    row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
    count(*) over (partition by a.ParentId) as TotalAnswers
  from Posts a
  left join Users u on a.OwnerUserId = u.Id
  where a.PostTypeId = 2
),
QuestionsWithTopAnswer as (
  select
    q.Id as QuestionId,
    q.Title,
    q.OwnerUserId,
    q.Score as QuestionScore,
    q.ViewCount,
    q.Tags,
    a.Id as TopAnswerId,
    a.AnswerOwner,
    a.Score as TopAnswerScore,
    a.CreationDate as TopAnswerCreationDate,
    a.TotalAnswers
  from RecentActivePosts q
  left join AnswersWithWindow a on a.ParentId = q.Id and a.AnswerRank = 1
  where q.PostTypeId = 1
),
CloseReasonsCount as (
  select
    ph.PostId,
    crt.Name as CloseReason,
    count(*) as CloseCount
  from PostHistory ph
  join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
  where ph.PostHistoryTypeId = 10
  group by ph.PostId, crt.Name
),
PostLinkAggregates as (
  select
    p.Id as QuestionId,
    count(distinct case when pl.LinkTypeId = 1 then pl.RelatedPostId end) as LinkedPostsCount,
    count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as DuplicatePostsCount
  from Posts p
  left join PostLinks pl on pl.PostId = p.Id
  where p.PostTypeId = 1
  group by p.Id
),
UserLatestAccessAndAvgVotes as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.LastAccessDate,
    avg(vt_up.VoteCount) filter (where vt_up.VoteTypeId = 2) over () as AvgUpVotes,
    avg(vt_down.VoteCount) filter (where vt_down.VoteTypeId = 3) over () as AvgDownVotes
  from Users u
  left join (
    select PostId, VoteTypeId, count(*) as VoteCount from Votes group by PostId, VoteTypeId
  ) vt_up on vt_up.PostId = (select p.Id from Posts p where p.OwnerUserId = u.Id order by p.CreationDate desc limit 1) and vt_up.VoteTypeId = 2
  left join (
    select PostId, VoteTypeId, count(*) as VoteCount from Votes group by PostId, VoteTypeId
  ) vt_down on vt_down.PostId = (select p2.Id from Posts p2 where p2.OwnerUserId = u.Id order by p2.CreationDate desc limit 1) and vt_down.VoteTypeId = 3
)
select
  q.QuestionId,
  q.Title,
  q.OwnerUserId,
  ubc.GoldBadges,
  ubc.SilverBadges,
  ubc.BronzeBadges,
  ubc.BadgesLastYear,
  q.QuestionScore,
  q.ViewCount,
  q.Tags,
  q.TopAnswerId,
  q.AnswerOwner,
  q.TopAnswerScore,
  q.TopAnswerCreationDate,
  q.TotalAnswers,
  cr.CloseReason,
  cr.CloseCount,
  pla.LinkedPostsCount,
  pla.DuplicatePostsCount,
  uli.LastAccessDate,
  uli.AvgUpVotes,
  uli.AvgDownVotes,
  case
    when q.ViewCount > 10000 and q.QuestionScore < 0 then 'Popular but controversial'
    when q.ViewCount < 100 and q.QuestionScore > 50 then 'Niche but highly rated'
    when q.TotalAnswers is null or q.TotalAnswers = 0 then 'Unanswered'
    else 'Normal'
  end as QuestionStatus,
  coalesce(nullif(length(q.Title), 0), 0) + coalesce(q.QuestionScore,0) as ComplexExpression,
  case
    when ubc.GoldBadges + ubc.SilverBadges + ubc.BronzeBadges = 0 then null
    else (ubc.GoldBadges * 3 + ubc.SilverBadges * 2 + ubc.BronzeBadges) * 1.0 / nullif(ubc.BadgesLastYear, 0)
  end as BadgeImpactRatio
from QuestionsWithTopAnswer q
left join UserBadgeCounts ubc on ubc.UserId = q.OwnerUserId
left join CloseReasonsCount cr on cr.PostId = q.QuestionId
left join PostLinkAggregates pla on pla.QuestionId = q.QuestionId
left join UserLatestAccessAndAvgVotes uli on uli.UserId = q.OwnerUserId
where q.Tags ilike '%sql%'
  and (cr.CloseCount is null or cr.CloseCount < 3)
order by BadgeImpactRatio desc nulls last, q.QuestionScore desc, q.ViewCount desc
limit 50;