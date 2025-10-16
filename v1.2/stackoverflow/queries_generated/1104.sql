-- {"query": "1104.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1508} 
with RankedPosts as (
  select
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    u.DisplayName as OwnerName,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Title,
    row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn,
    coalesce(p.Tags,'') as Tags
  from Posts p
  left join Users u on p.OwnerUserId = u.Id
  where p.PostTypeId in (1,2)
),
FilteredPosts as (
  select * from RankedPosts where rn <= 1000
),
AnswerCounts as (
  select ParentId as QuestionId, count(*) as AnswerCount
  from Posts
  where PostTypeId = 2
  group by ParentId
),
BadgeDist as (
  select 
    UserId,
    sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
  from Badges
  group by UserId
),
RecentComments as (
  select
    c.PostId,
    count(*) filter (where c.CreationDate > current_date - interval '30 days') as RecentCommentsCount,
    max(c.CreationDate) as LastCommentDate
  from Comments c
  group by c.PostId
),
PostLinkSummary as (
  select
    pl.PostId,
    count(case when lt.Name = 'Linked' then 1 end) as LinkedPosts,
    count(case when lt.Name = 'Duplicate' then 1 end) as DuplicatePosts
  from PostLinks pl
  join LinkTypes lt on pl.LinkTypeId = lt.Id
  group by pl.PostId
),
PostCloseReasons as (
  select
    ph.PostId,
    string_agg(distinct crt.Name, ', ') as CloseReasons,
    max(ph.CreationDate) as LastCloseDate
  from PostHistory ph
  join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
  left join CloseReasonTypes crt on try_cast(ph.Comment as int) = crt.Id
  where ph.PostHistoryTypeId = 10
  group by ph.PostId
),
UserActivityWindow as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    count(distinct p.Id) filter (where p.CreationDate > u.CreationDate + interval '365 days') over (partition by u.Id) as PostsInFirstYear,
    count(distinct v.Id) filter (where v.CreationDate > u.CreationDate + interval '365 days') over (partition by u.Id) as VotesInFirstYear,
    count(distinct b.Id) filter (where b.Date > u.CreationDate + interval '365 days') over (partition by u.Id) as BadgesInFirstYear
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Votes v on v.UserId = u.Id
  left join Badges b on b.UserId = u.Id
),
CorrelatedTagCount as (
  select
    p.Id,
    (select count(*) from unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as tag(t)
       where exists (select 1 from Tags tg where tg.TagName = tag.t and tg.Count > 1000)
    ) as PopularTagCount
  from Posts p
  where p.PostTypeId = 1
)
select
  p.Id as PostId,
  p.PostTypeId,
  case when p.PostTypeId = 1 then 'Question' else 'Answer' end as PostType,
  p.Title,
  p.Score,
  p.ViewCount,
  ac.AnswerCount,
  r.RecentCommentsCount,
  r.LastCommentDate,
  pls.LinkedPosts,
  pls.DuplicatePosts,
  coalesce(pcr.CloseReasons, 'None') as CloseReasons,
  coalesce(ub.GoldBadges,0) as OwnerGoldBadges,
  coalesce(ub.SilverBadges,0) as OwnerSilverBadges,
  coalesce(ub.BronzeBadges,0) as OwnerBronzeBadges,
  ca.PopularTagCount,
  u.DisplayName as OwnerDisplayName,
  u.Reputation as OwnerReputation,
  u.LastAccessDate,
  ua.PostsInFirstYear,
  ua.VotesInFirstYear,
  ua.BadgesInFirstYear,
  case 
    when p.Score > 100 and p.ViewCount > 10000 then 'High Impact'
    when p.Score between 50 and 100 then 'Medium Impact'
    else 'Low Impact'
  end as ImpactCategory,
  left(p.Title || coalesce(u.DisplayName, 'Anonymous') || coalesce(pcr.CloseReasons, ''), 100) as CombinedTextField
from FilteredPosts p
left join AnswerCounts ac on ac.QuestionId = p.Id
left join RecentComments r on r.PostId = p.Id
left join PostLinkSummary pls on pls.PostId = p.Id
left join PostCloseReasons pcr on pcr.PostId = p.Id
left join BadgeDist ub on ub.UserId = p.OwnerUserId
left join Users u on u.Id = p.OwnerUserId
left join UserActivityWindow ua on ua.Id = p.OwnerUserId
left join CorrelatedTagCount ca on ca.Id = p.Id
where
  (p.Score > 10 or coalesce(ac.AnswerCount,0) > 1 or ca.PopularTagCount > 0)
  and (r.RecentCommentsCount is null or r.RecentCommentsCount > 0)
union
select
  p2.Id,
  p2.PostTypeId,
  case when p2.PostTypeId = 1 then 'Question' else 'Answer' end as PostType,
  null as Title,
  p2.Score,
  p2.ViewCount,
  0 as AnswerCount,
  0 as RecentCommentsCount,
  null as LastCommentDate,
  0 as LinkedPosts,
  0 as DuplicatePosts,
  'No CloseReasons' as CloseReasons,
  0 as OwnerGoldBadges,
  0 as OwnerSilverBadges,
  0 as OwnerBronzeBadges,
  0 as PopularTagCount,
  null as OwnerDisplayName,
  0 as OwnerReputation,
  null as LastAccessDate,
  0 as PostsInFirstYear,
  0 as VotesInFirstYear,
  0 as BadgesInFirstYear,
  'Low Impact' as ImpactCategory,
  '' as CombinedTextField
from Posts p2
where not exists (select 1 from FilteredPosts fp where fp.Id = p2.Id)
order by PostType, Score desc, ViewCount desc
limit 50;