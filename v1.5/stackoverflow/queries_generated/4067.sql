-- {"query": "4067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 975} 
with recursive TagHierarchy as (
    select t.Id, t.TagName, 1 as Level, array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0
  union all
    select t2.Id, t2.TagName, th.Level+1, th.Path || t2.TagName
    from Tags t2
    inner join TagHierarchy th on t2.ExcerptPostId = th.Id
    where not t2.TagName = any(th.Path)
), TopUsers as (
    select u.Id, u.DisplayName, u.Reputation,
      row_number() over (order by u.Reputation desc nulls last, u.CreationDate asc) as rn
    from Users u
    where u.Reputation > 1000 and u.Location is not null
), RecentBadges as (
    select b.UserId, b.Name as BadgeName, b.Date,
      dense_rank() over (partition by b.UserId order by b.Date desc) as dr
    from Badges b
    where b.Class = 1 -- gold badges only
), PostsWithDetails as (
    select p.Id, p.Title, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate, p.Tags,
      (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
      (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
      row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByType
    from Posts p
    where p.PostTypeId in (1,2) -- questions and answers
      and p.CreationDate > now() - interval '365 days'
), LinkedQuestions as (
    select pl.PostId, pl.RelatedPostId,
      max(case when pl.LinkTypeId = 3 then 1 else 0 end) as HasDuplicateLink
    from PostLinks pl
    group by pl.PostId, pl.RelatedPostId
), CommentsCountByUser as (
    select c.UserId, count(*) as CommentCount
    from Comments c
    group by c.UserId
)
select u.Id as UserId, u.DisplayName, u.Reputation, u.Location,
  coalesce(cb.BadgeName, 'No Gold Badge') as LatestGoldBadge,
  coalesce(pc.Score, 0) as PostScore,
  coalesce(pc.Title, '[no title]') as PostTitle,
  pc.ViewCount,
  pc.Tags,
  pc.RankByType,
  coalesce(lq.HasDuplicateLink, 0) as HasDuplicateOnPosts,
  coalesce(cc.CommentCount, 0) as TotalComments,
  case
    when u.Reputation > 50000 then 'Elite'
    when u.Reputation between 10000 and 50000 then 'Experienced'
    else 'Intermediate'
  end as UserTier,
  case
    when pc.PostTypeId = 1 then substring(pc.Tags from '<([^>]+)>') -- extract first tag
    else null
  end as FirstTag,
  length(coalesce(pc.Title, '')) as TitleLength,
  (select count(*) from Posts ap where ap.ParentId = pc.Id) as AnswerCountForQuestion,
  (
    select avg(p2.Score)
    from Posts p2
    where p2.OwnerUserId = u.Id
      and p2.PostTypeId = 2
  ) as AvgAnswerScore,
  (select count(*) from Votes v2 where v2.PostId = pc.Id and v2.UserId = u.Id) as SelfVotesCount,
  sum(case when ph.PostHistoryTypeId in (10,12) then 1 else 0 end) as CloseOrDeleteEvents
from TopUsers u
left join RecentBadges cb on cb.UserId = u.Id and cb.dr = 1
left join PostsWithDetails pc on pc.OwnerUserId = u.Id and pc.RankByType <= 5
left join LinkedQuestions lq on lq.PostId = pc.Id
left join CommentsCountByUser cc on cc.UserId = u.Id
left join PostHistory ph on ph.PostId = pc.Id and ph.UserId = u.Id
where exists (
  select 1 from Tags tg
  where tg.TagName = any(string_to_array(replace(pc.Tags,'><',','), ','))
    and tg.Count > 1000
)
order by u.Reputation desc, pc.Score desc
limit 50;