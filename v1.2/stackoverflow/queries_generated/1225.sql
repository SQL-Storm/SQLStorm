-- {"query": "1225.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1214} 
with RecursiveUserBadgeCounts as (
  select 
    u.Id as UserId,
    u.DisplayName,
    b.Class,
    count(*) as BadgeCount
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, b.Class

  union all

  select
    r.UserId,
    r.DisplayName,
    case when r.Class is null then 3 else r.Class end + 1,
    0
  from RecursiveUserBadgeCounts r
  where r.Class is null or r.Class < 3
),
TopUsersByBadgeTypes as (
  select
    UserId,
    DisplayName,
    coalesce(max(case when Class = 1 then BadgeCount end), 0) as GoldBadges,
    coalesce(max(case when Class = 2 then BadgeCount end), 0) as SilverBadges,
    coalesce(max(case when Class = 3 then BadgeCount end), 0) as BronzeBadges
  from RecursiveUserBadgeCounts
  group by UserId, DisplayName
),
QuestionAnswerStats as (
  select
    p.Id as QuestionId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.OwnerUserId,
    p.Score as QuestionScore,
    coalesce(a.AnswerCount,0) as AnswerCount,
    coalesce(a.AverageAnswerScore,0) as AverageAnswerScore,
    coalesce(a.MaxAnswerScore, 0) as MaxAnswerScore,
    p.Tags
  from Posts p
  left join (
    select 
      ParentId, 
      count(*) as AnswerCount,
      avg(Score) as AverageAnswerScore,
      max(Score) as MaxAnswerScore
    from Posts
    where PostTypeId = 2
    group by ParentId
  ) a on a.ParentId = p.Id
  where p.PostTypeId = 1
    and p.CreationDate > now() - interval '5 year'
),
RankedQuestions as (
  select
    q.*,
    row_number() over (partition by q.OwnerUserId order by q.Score desc, q.ViewCount desc) as QuestionRank
  from QuestionAnswerStats q
  where q.OwnerUserId is not null
),
FilteredQuestions as (
  select *
  from RankedQuestions
  where QuestionRank <= 3
),
CorrelationBountyVotes as (
  select
    p.OwnerUserId,
    p.Id as PostId,
    sum(v.BountyAmount) as TotalBountyAwarded
  from Posts p 
  left join Votes v 
    on v.PostId = p.Id and v.VoteTypeId = 9
  where p.OwnerUserId is not null and p.PostTypeId in (1,2)
  group by p.OwnerUserId, p.Id
),
QuestionCloseReasons as (
  select
    ph.PostId,
    crt.Name as CloseReasonName,
    ph.CreationDate as ClosedAt
  from PostHistory ph
  join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
  left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer) -- Note: safe cast assumption
),
UserLastActivity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    max(p.LastActivityDate) as LastPostActivity,
    max(c.CreationDate) as LastCommentDate,
    max(v.CreationDate) as LastVoteDate,
    greatest(
      max(p.LastActivityDate),
      max(c.CreationDate),
      max(v.CreationDate),
      u.LastAccessDate
    ) as LastOverallActivity
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  left join Votes v on v.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
)

select
  u.UserId,
  u.DisplayName,
  u.Reputation,
  ub.GoldBadges,
  ub.SilverBadges,
  ub.BronzeBadges,
  u.LastOverallActivity,
  fq.QuestionId,
  fq.Title as QuestionTitle,
  fq.CreationDate as QuestionCreated,
  fq.ViewCount,
  fq.QuestionScore,
  fq.AnswerCount,
  fq.AverageAnswerScore,
  fq.MaxAnswerScore,
  qcr.CloseReasonName,
  qbv.TotalBountyAwarded,
  substr(fq.Tags, 0, 100) as TagsSample,
  case 
    when fq.QuestionScore > 100 and fq.AnswerCount > 10 then 'Hot Topic'
    when fq.ViewCount > 10000 then 'Popular'
    when fq.Chat is null then 'Needs Attention'
    else 'Normal'
  end as QuestionStatus,
  row_number() over (partition by u.UserId order by fq.QuestionScore desc) as UserQuestionRank
from UserLastActivity u
inner join TopUsersByBadgeTypes ub on ub.UserId = u.UserId
left join FilteredQuestions fq on fq.OwnerUserId = u.UserId
left join QuestionCloseReasons qcr on qcr.PostId = fq.QuestionId
left join CorrelationBountyVotes qbv on qbv.PostId = fq.QuestionId
where u.Reputation > 5000
  and (fq.AnswerCount > 2 or fq.AnswerCount is null)
  and (qbv.TotalBountyAwarded > 0 or qbv.TotalBountyAwarded is null)
order by u.Reputation desc, ub.GoldBadges desc, fq.QuestionScore desc
limit 100;