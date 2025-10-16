-- {"query": "1046.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1340} 
with RecursiveUserBadges as (
  select u.Id as UserId, u.DisplayName, u.Reputation, b.Name as BadgeName, b.Class, b.Date,
    row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
  from Users u
  left join Badges b on b.UserId = u.Id and b.Class = 1
  where u.Reputation > 1000
  union all
  select u.UserId, u.DisplayName, u.Reputation, b.Name, b.Class, b.Date,
    u.BadgeRank + 1
  from RecursiveUserBadges u
  join Badges b on b.UserId = u.UserId and b.Date < u.Date and b.Class = 2
  where u.BadgeRank < 3
),
TopUserPosts as (
  select p.OwnerUserId, p.Id as PostId, p.PostTypeId, p.Score, p.CreationDate,
    rank() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate asc) as PostScoreRank,
    count(c.Id) as CommentCount
  from Posts p
  left join Comments c on c.PostId = p.Id
  where p.OwnerUserId is not null
  group by p.OwnerUserId, p.Id, p.PostTypeId, p.Score, p.CreationDate
  having p.Score > 0
),
QuestionAnswerStats as (
  select q.Id as QuestionId,
    q.Title as QuestionTitle,
    q.CreationDate as QuestionDate,
    coalesce(a.AnswerCount, 0) as TotalAnswers,
    coalesce(avg(ans.Score), 0) as AvgAnswerScore,
    coalesce(max(ans.Score), 0) as MaxAnswerScore
  from Posts q
  left join (
    select ParentId, count(*) as AnswerCount
    from Posts
    where PostTypeId = 2
    group by ParentId
  ) a on a.ParentId = q.Id
  left join Posts ans on ans.ParentId = q.Id and ans.PostTypeId = 2
  where q.PostTypeId = 1 and q.Score > 5
  group by q.Id, q.Title, q.CreationDate, a.AnswerCount
),
PostHistoryLastEdits as (
  select ph.PostId,
    max(ph.CreationDate) as LastEditDate,
    max(case when ph.PostHistoryTypeId in (4,5,6) then ph.UserId else null end) as LastEditorUserId
  from PostHistory ph
  where ph.PostHistoryTypeId in (4,5,6)
  group by ph.PostId
),
PostsWithHistories as (
  select p.Id, p.Title, p.Score, p.ViewCount, p.Tags, p.CreationDate, p.OwnerUserId,
    phle.LastEditDate, phle.LastEditorUserId
  from Posts p
  left join PostHistoryLastEdits phle on phle.PostId = p.Id
)
select u.Id as UserId, u.DisplayName,
  count(distinct p.Id) as TotalPosts,
  sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
  sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
  max(p.Score) as MaxPostScore,
  avg(p.Score) as AvgPostScore,
  coalesce(b.BadgeNames, 'No badges') as TopBadges,
  qas.TotalAnswers,
  qas.AvgAnswerScore,
  qas.MaxAnswerScore,
  substr(p.Tags, 1, 100) as SampleTags,
  case when p.ViewCount > 10000 then 'Popular' else 'Regular' end as PopularityCategory,
  usrBadges.BadgeName as RecursiveBadgeName,
  usrBadges.Class as RecursiveBadgeClass,
  ph.Id as HistoryId,
  ph.PostHistoryTypeId,
  ph.CreationDate as HistoryCreationDate,
  case 
    when ph.PostHistoryTypeId in (10,11) then (select Name from CloseReasonTypes cr where cr.Id::text = ph.Comment)
    else 'N/A'
  end as CloseReasonName
from Users u
join Posts p on p.OwnerUserId = u.Id
left join (
  select UserId,
    string_agg(distinct Name, ', ' order by Date desc) as BadgeNames
  from Badges
  group by UserId
) b on b.UserId = u.Id
left join QuestionAnswerStats qas on qas.QuestionId = p.Id and p.PostTypeId = 1
left join RecursiveUserBadges usrBadges on usrBadges.UserId = u.Id and usrBadges.BadgeRank = 1
left join PostHistory ph on ph.PostId = p.Id and ph.CreationDate = (
  select max(ph2.CreationDate) from PostHistory ph2 where ph2.PostId = p.Id
)
where u.Reputation > 500 and p.Score > 0
group by u.Id, u.DisplayName, b.BadgeNames, qas.TotalAnswers, qas.AvgAnswerScore,
  qas.MaxAnswerScore, p.Tags, p.ViewCount, usrBadges.BadgeName, usrBadges.Class,
  ph.Id, ph.PostHistoryTypeId, ph.CreationDate, ph.Comment
order by u.Reputation desc, MaxPostScore desc
union
select u.Id as UserId, u.DisplayName,
  0 as TotalPosts, 0 as QuestionCount, 0 as AnswerCount, 0 as MaxPostScore, 0 as AvgPostScore,
  'No badges' as TopBadges,
  0 as TotalAnswers, 0 as AvgAnswerScore, 0 as MaxAnswerScore,
  null as SampleTags,
  'Inactive' as PopularityCategory,
  null as RecursiveBadgeName,
  null as RecursiveBadgeClass,
  null as HistoryId,
  null as PostHistoryTypeId,
  null as HistoryCreationDate,
  null as CloseReasonName
from Users u
where not exists (
  select 1 from Posts p where p.OwnerUserId = u.Id
)
and u.Reputation > 500
order by Reputation desc
limit 100;