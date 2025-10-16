-- {"query": "1290.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1099} 
with RecursiveBadgeCounts as (
  select 
    u.Id as UserId,
    u.DisplayName,
    b.Class,
    count(*) as BadgeCount
  from Users u
  left join Badges b on u.Id = b.UserId
  group by u.Id, u.DisplayName, b.Class

  union all

  select
    rbc.UserId,
    rbc.DisplayName,
    case rbc.Class
      when 1 then 2
      when 2 then 3
      when 3 then null
      else null
    end,
    rbc.BadgeCount - 1
  from RecursiveBadgeCounts rbc
  where rbc.Class in (1, 2)
),
UserTopTags as (
  select
    u.Id as UserId,
    t.TagName,
    count(p.Id) as TagPostCount
  from Users u
  join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
  cross join lateral (
    select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName
  ) as t
  group by u.Id, t.TagName
  having count(p.Id) > 5
),
QuestionAnswerStats as (
  select
    q.Id as QuestionId,
    q.Title,
    q.CreationDate as QuestionCreation,
    q.Score as QuestionScore,
    q.ViewCount,
    coalesce(a.AnswerCount, 0) as AnswerCount,
    coalesce(a.MaxScore, 0) as MaxAnswerScore,
    coalesce(a.AvgScore, 0) as AvgAnswerScore,
    a.TopAnswerUserId,
    u.DisplayName as TopAnswerUserName
  from Posts q
  left join lateral (
    select 
      p.ParentId, 
      count(*) as AnswerCount, 
      max(p.Score) as MaxScore,
      avg(p.Score)::float as AvgScore,
      (select p2.OwnerUserId from Posts p2 where p2.ParentId = q.Id order by p2.Score desc nulls last limit 1) as TopAnswerUserId
    from Posts p
    where p.PostTypeId = 2 and p.ParentId = q.Id
    group by p.ParentId
  ) a on q.Id = a.ParentId
  left join Users u on u.Id = a.TopAnswerUserId
  where q.PostTypeId = 1
),
CloseReasonAggregated as (
  select cht.Id as PostHistoryTypeId, cr.Name as CloseReasonName, count(*) as CloseCount
  from PostHistory cht
  join CloseReasonTypes cr on cast(cht.Comment as int) = cr.Id and cht.PostHistoryTypeId = 10
  group by cht.Id, cr.Name
),
UserActivityWindow as (
  select
    p.OwnerUserId,
    p.Id as PostId,
    p.PostTypeId,
    p.Score,
    row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
    count(tv.Id) filter (where tv.VoteTypeId = 2) over (partition by p.OwnerUserId order by p.CreationDate rows between unbounded preceding and current row) as TotalUpVotesReceived
  from Posts p
  left join Votes tv on tv.PostId = p.Id
  where p.OwnerUserId is not null and p.OwnerUserId > 0
)
select 
  qa.QuestionId,
  qa.Title,
  qa.ViewCount,
  qa.QuestionScore,
  qa.AnswerCount,
  qa.MaxAnswerScore,
  qa.AvgAnswerScore,
  qa.TopAnswerUserName,
  string_agg(distinct ut.TagName, ', ') as UserTopTags,
  sum(case when rbc.Class = 1 then rbc.BadgeCount else 0 end) as GoldBadgesCount,
  sum(case when rbc.Class = 2 then rbc.BadgeCount else 0 end) as SilverBadgesCount,
  sum(case when rbc.Class = 3 then rbc.BadgeCount else 0 end) as BronzeBadgesCount,
  max(cr.CloseCount) as MostCommonCloseCount,
  count(distinct ua.PostId) filter (where ua.RecentPostRank <= 5) as RecentPostsByUser,
  max(ua.TotalUpVotesReceived) as TotalUpVotesReceivedByUser
from QuestionAnswerStats qa
left join Users u on u.DisplayName = qa.TopAnswerUserName
left join UserTopTags ut on ut.UserId = u.Id
left join RecursiveBadgeCounts rbc on rbc.UserId = u.Id
left join CloseReasonAggregated cr on cr.PostHistoryTypeId = 10
left join UserActivityWindow ua on ua.OwnerUserId = u.Id
group by 
  qa.QuestionId,
  qa.Title,
  qa.ViewCount,
  qa.QuestionScore,
  qa.AnswerCount,
  qa.MaxAnswerScore,
  qa.AvgAnswerScore,
  qa.TopAnswerUserName
having count(distinct ua.PostId) filter (where ua.RecentPostRank <= 5) >= 3
order by qa.ViewCount desc
limit 25;