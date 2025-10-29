-- {"query": "2968.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1458} 
with 
UserPostCounts as (
  select 
    u.Id as UserId,
    u.DisplayName,
    count(distinct p.Id) as TotalPosts,
    count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
    count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
    coalesce(sum(p.Score),0) as TotalPostScore,
    max(p.Score) as MaxPostScore,
    sum(case when p.ViewCount is null then 0 else p.ViewCount end) as TotalViews,
    avg(case when p.Score is null then 0 else p.Score end) as AvgScore
  from 
    Users u
    left join Posts p on p.OwnerUserId = u.Id
  group by u.Id, u.DisplayName
),
UserBadgeRanks as (
  select 
    UserId,
    -- Assign a weighted rank for badges gold=3, silver=2, bronze=1
    sum(case BadgeClass when 1 then 3 when 2 then 2 when 3 then 1 else 0 end) as BadgeScore,
    count(*) as BadgeCount,
    count(distinct case when TagBased = 1 then Id end) as TagBasedBadges
  from 
    (select 
       Id, UserId, Class as BadgeClass, TagBased 
     from Badges) b
  group by UserId
),
RecentUserEdits as (
  select distinct
    ph.UserId,
    count(*) over (partition by ph.UserId) as EditCount,
    max(ph.CreationDate) over (partition by ph.UserId) as LastEditDate
  from PostHistory ph
  where ph.PostHistoryTypeId in (4,5,6,14) -- Edit Title, Body, Tags, Suggested Edit Applied
),
QuestionsWithDuplicates as (
  select 
    p.Id,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    pl.RelatedPostId as DuplicateOfId,
    p.OwnerUserId
  from Posts p
  left join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3 -- duplicates
  where p.PostTypeId = 1
),
RankedAnswers as (
  select 
    p.Id,
    p.ParentId,
    p.Score,
    row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate) as AnswerRank,
    p.CreationDate,
    p.OwnerUserId
  from Posts p
  where p.PostTypeId = 2
),
TopTags as (
  select 
    t.TagName, 
    t.Count, 
    p.Id as PostId,
    p.Tags,
    p.OwnerUserId
  from Tags t
  join Posts p on p.Id = t.ExcerptPostId
  where t.Count > 1000
),
UserTagAffinity as (
  select 
    upc.UserId,
    unnest(string_to_array(replace(replace(coalesce(p.Tags,'<>'),'<',''),'>',' '))::text[]) as Tag,
    count(*) as TagPostCount
  from Users u
  join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
  join UserPostCounts upc on upc.UserId = u.Id
  group by upc.UserId, Tag
),
UserTopTags as (
  select distinct on (UserId) 
    UserId,
    Tag as TopTag,
    TagPostCount
  from UserTagAffinity
  order by UserId, TagPostCount desc
)
select 
  u.Id as UserId,
  u.DisplayName,
  upc.TotalPosts,
  upc.QuestionCount,
  upc.AnswerCount,
  upc.TotalPostScore,
  ubr.BadgeScore,
  ubr.BadgeCount,
  ubr.TagBasedBadges,
  coalesce(re.Edits,0) as TotalEdits,
  re.LastEditDate,
  coalesce(favq.FavoriteCount,0) as FavoriteQuestions,
  coalesce(topTags.TopTag, 'no tag') as FavoriteTag,
  coalesce(topTags.TagPostCount,0) as TagPostCount,
  dupq.DuplicateQuestions,
  bestAns.BestAnswerId,
  bestAns.BestAnswerScore,
  bestAns.BestAnswerAgeDays,
  case 
    when upc.AvgScore > 5 and ubr.BadgeScore > 5 then 'Elite'
    when upc.AvgScore > 2 then 'Contributor'
    else 'Newbie'
  end as UserTier
from Users u
left join UserPostCounts upc on upc.UserId = u.Id
left join UserBadgeRanks ubr on ubr.UserId = u.Id
left join (
  select UserId, count(*) as Edits, max(CreationDate) as LastEditDate
  from PostHistory
  where UserId is not null and PostHistoryTypeId in (4,5,6,14)
  group by UserId
) re on re.UserId = u.Id
left join (
  select p.OwnerUserId, count(*) as FavoriteCount
  from Posts p
  where p.FavoriteCount is not null
  group by p.OwnerUserId
) favq on favq.OwnerUserId = u.Id
left join (
  select UserId, TopTag, TagPostCount
  from UserTopTags
) topTags on topTags.UserId = u.Id
left join (
  select 
    p.OwnerUserId,
    count(*) filter (where pl.Id is not null) as DuplicateQuestions
  from Posts p
  left join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
  where p.PostTypeId = 1
  group by p.OwnerUserId
) dupq on dupq.OwnerUserId = u.Id
left join (
  select 
    ra.OwnerUserId,
    ra.Id as BestAnswerId,
    ra.Score as BestAnswerScore,
    extract(day from now() - ra.CreationDate) as BestAnswerAgeDays
  from RankedAnswers ra
  where ra.AnswerRank = 1
) bestAns on bestAns.OwnerUserId = u.Id
where 
  (upc.TotalPosts > 10 or ubr.BadgeCount > 2)
  and (
    (upc.AvgScore > 3 or ubr.BadgeScore > 5)
    or 
    exists (
      select 1 from Posts p2 
      where p2.OwnerUserId = u.Id and p2.PostTypeId=1 and p2.ClosedDate is null
      and p2.CreationDate > now() - interval '30 days'
    )
  )
order by upc.TotalPostScore desc, ubr.BadgeScore desc
limit 100;