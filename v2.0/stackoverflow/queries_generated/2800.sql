-- {"query": "2800.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1424} 
with RecursiveTagCounts as (
  select
    t.TagName,
    t.Count,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    p.ViewCount,
    p.Score,
    p.Id as PostId
  from Tags t
  left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
),
UserBadgeStats as (
  select
    u.Id as UserId,
    u.DisplayName,
    count(b.Id) filter (where b.Class = 1) as GoldBadges,
    count(b.Id) filter (where b.Class = 2) as SilverBadges,
    count(b.Id) filter (where b.Class = 3) as BronzeBadges,
    avg(b.Class) filter (where b.TagBased = 0) as AvgBadgeClass,
    max(b.Date) as LastBadgeDate
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName
),
PostActivityWindow as (
  select
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    row_number() over (partition by p.OwnerUserId order by p.CreationDate) as UserPostRank,
    lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
    lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
  from Posts p
  where p.OwnerUserId is not null
),
ClosedQuestionsWithReasons as (
  select
    ph.PostId,
    cr.Name as CloseReason,
    ph.CreationDate as CloseDate,
    ph.UserId as ClosedByUserId,
    u.DisplayName as ClosedByUser
  from PostHistory ph
  join CloseReasonTypes cr on cr.Id = cast(ph.Comment as int) -- stored close reason id as text in Comment
  left join Users u on u.Id = ph.UserId
  where ph.PostHistoryTypeId = 10 -- Post Closed
),
AnswersWithParentInfo as (
  select
    a.Id,
    a.ParentId,
    q.Title as QuestionTitle,
    q.Tags,
    q.OwnerUserId as QuestionOwner,
    a.Score,
    a.CreationDate,
    a.OwnerUserId,
    case
      when a.CreationDate < q.CreationDate + interval '1 day' then 1 else 0 end as AnsweredWithin1Day
  from Posts a
  join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
  where a.PostTypeId = 2
),
UserActivitySummary as (
  select
    u.Id,
    u.DisplayName,
    count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
    count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
    sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalScore,
    max(p.CreationDate) as LastPostDate,
    count(distinct c.Id) as CommentCount,
    sum(v.VoteTypeId = 2)::int as UpVotesReceived,
    sum(v.VoteTypeId = 3)::int as DownVotesReceived
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  left join Votes v on v.PostId = p.Id
  group by u.Id, u.DisplayName
)

select
  r.TagName,
  r.Count as TagUseCount,
  r.ViewCount,
  r.Score as TagExcerptScore,
  r.AnswerCount as TagExcerptAnswerCount,
  u.DisplayName as TopUserForTag,
  u.Reputation,
  ubs.GoldBadges,
  ubs.SilverBadges,
  ubs.BronzeBadges,
  ubs.AvgBadgeClass,
  ca.CloseReason,
  ca.CloseDate,
  ca.ClosedByUser,
  a.AnsweredWithin1Day,
  uas.QuestionCount,
  uas.AnswerCount,
  uas.TotalScore,
  uas.CommentCount,
  uas.UpVotesReceived,
  uas.DownVotesReceived
from RecursiveTagCounts r
left join Lateral (
  select u.Id, u.DisplayName, u.Reputation
  from Users u
  join Posts p2 on p2.OwnerUserId = u.Id and p2.Tags like concat('%<', r.TagName, '>%')
  order by u.Reputation desc nulls last
  limit 1
) u on true
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join ClosedQuestionsWithReasons ca on ca.PostId = r.PostId
left join AnswersWithParentInfo a on a.ParentId = r.PostId
left join UserActivitySummary uas on uas.Id = r.PostId
where r.Count > 1000
union
select
  t.TagName,
  t.Count,
  null, null, null,
  null, null, null, null, null,
  null, null, null,
  null, null, null, null, null, null
from Tags t
where t.IsModeratorOnly = 1
except
select
  r.TagName,
  r.Count,
  r.ViewCount,
  r.Score,
  r.AnswerCount,
  u.DisplayName,
  u.Reputation,
  ubs.GoldBadges,
  ubs.SilverBadges,
  ubs.BronzeBadges,
  ubs.AvgBadgeClass,
  ca.CloseReason,
  ca.CloseDate,
  ca.ClosedByUser,
  a.AnsweredWithin1Day,
  uas.QuestionCount,
  uas.AnswerCount,
  uas.TotalScore,
  uas.CommentCount,
  uas.UpVotesReceived,
  uas.DownVotesReceived
from RecursiveTagCounts r
left join Lateral (
  select u.Id, u.DisplayName, u.Reputation
  from Users u
  join Posts p2 on p2.OwnerUserId = u.Id and p2.Tags like concat('%<', r.TagName, '>%')
  order by u.Reputation desc nulls last
  limit 1
) u on true
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join ClosedQuestionsWithReasons ca on ca.PostId = r.PostId
left join AnswersWithParentInfo a on a.ParentId = r.PostId
left join UserActivitySummary uas on uas.Id = r.PostId
where r.Count <= 1000
order by TagUseCount desc, Reputation desc nulls last
limit 100;