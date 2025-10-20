with recursive RecursiveUserBadges as (
  select u.Id as UserId, u.DisplayName, u.Reputation, b.Name as BadgeName, b.Class, b.Date,
    row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
  from Users u
  left join Badges b on b.UserId = u.Id and b.Class = 1
  where u.Reputation > 1000
  union all
  select r.UserId, r.DisplayName, r.Reputation, b.Name, b.Class, b.Date,
    r.BadgeRank + 1
  from RecursiveUserBadges r
  join Badges b on b.UserId = r.UserId and b.Date < r.Date and b.Class = 2
  where r.BadgeRank < 3
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
),
MainActiveUsers as (
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
      when ph.PostHistoryTypeId in (10,11) then (select cr.Name from CloseReasonTypes cr where cast(cr.Id as varchar) = ph.Comment)
      else 'N/A'
    end as CloseReasonName,
    u.Reputation as UserReputation,
    p.Tags as FullTags,
    p.ViewCount as FullViewCount,
    ph.Comment as HistoryComment
  from Users u
  join Posts p on p.OwnerUserId = u.Id
  left join (
    select UserId,
      -- Standard SQL: aggregate distinct values while allowing ORDER BY by using array_agg of structs or string aggregation without DISTINCT but with a subquery to order first.
      -- Here we build BadgeNames by concatenating names ordered by Date descending per user.
      (select string_agg(bn.Name, ', ')
       from (
         select Name
         from Badges b2
         where b2.UserId = b1.UserId
         order by Date desc
       ) bn
      ) as BadgeNames
    from (
      select distinct UserId from Badges
    ) b1
  ) b on b.UserId = u.Id
  left join QuestionAnswerStats qas on qas.QuestionId = p.Id and p.PostTypeId = 1
  left join RecursiveUserBadges usrBadges on usrBadges.UserId = u.Id and usrBadges.BadgeRank = 1
  left join PostHistory ph on ph.PostId = p.Id and ph.CreationDate = (
    select max(ph2.CreationDate) from PostHistory ph2 where ph2.PostId = p.Id
  )
  where u.Reputation > 500 and p.Score > 0
  group by u.Id, u.DisplayName, b.BadgeNames, qas.TotalAnswers, qas.AvgAnswerScore,
    qas.MaxAnswerScore, p.Tags, p.ViewCount, usrBadges.BadgeName, usrBadges.Class,
    ph.Id, ph.PostHistoryTypeId, ph.CreationDate, ph.Comment, u.Reputation, p.Tags, p.ViewCount
),
InactiveUsers as (
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
    null as CloseReasonName,
    u.Reputation as UserReputation,
    null as FullTags,
    null as FullViewCount,
    null as HistoryComment
  from Users u
  where not exists (
    select 1 from Posts p where p.OwnerUserId = u.Id
  )
  and u.Reputation > 500
)
select *
from (
  select UserId, DisplayName, TotalPosts, QuestionCount, AnswerCount, MaxPostScore, AvgPostScore,
    TopBadges, TotalAnswers, AvgAnswerScore, MaxAnswerScore, SampleTags, PopularityCategory,
    RecursiveBadgeName, RecursiveBadgeClass, HistoryId, PostHistoryTypeId, HistoryCreationDate, CloseReasonName,
    UserReputation, FullTags, FullViewCount, HistoryComment
  from MainActiveUsers
  union
  select UserId, DisplayName, TotalPosts, QuestionCount, AnswerCount, MaxPostScore, AvgPostScore,
    TopBadges, TotalAnswers, AvgAnswerScore, MaxAnswerScore, SampleTags, PopularityCategory,
    RecursiveBadgeName, RecursiveBadgeClass, HistoryId, PostHistoryTypeId, HistoryCreationDate, CloseReasonName,
    UserReputation, FullTags, FullViewCount, HistoryComment
  from InactiveUsers
) combined
order by UserReputation desc, MaxPostScore desc
limit 100;