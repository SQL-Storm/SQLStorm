-- {"query": "1072.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1000} 
with RecursiveCTE as (
    select p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.ViewCount, p.CreationDate,
           p.AcceptedAnswerId,
           dense_rank() over (partition by p.OwnerUserId order by p.CreationDate) as PostRank,
           1 as Level
      from Posts p
     where p.PostTypeId = 1 -- questions
       and p.Score > 5
    union all
    select p2.Id, p2.OwnerUserId, p2.PostTypeId, p2.Score, p2.ViewCount, p2.CreationDate,
           p2.AcceptedAnswerId,
           dense_rank() over (partition by p2.OwnerUserId order by p2.CreationDate) as PostRank,
           r.Level + 1
      from Posts p2
      join RecursiveCTE r on p2.OwnerUserId = r.OwnerUserId
     where p2.PostTypeId in (2) -- answers
       and p2.ParentId = r.Id
       and p2.Score > r.Score/2
       and r.Level < 3
), UserBadgeCounts as (
    select b.UserId,
           b.Class,
           count(*) as BadgeCount
      from Badges b
     group by b.UserId, b.Class
), LatestComments as (
    select c.PostId,
           c.Id as CommentId,
           c.UserId as CommentUserId,
           c.CreationDate as CommentDate,
           row_number() over (partition by c.PostId order by c.CreationDate desc) as rn
      from Comments c
), UserReputationWindow as (
    select u.Id, u.Reputation, u.CreationDate,
           avg(u.Reputation) over (order by u.CreationDate rows between 999 preceding and current row) as AvgReputationLast1000Users,
           count(*) over () as TotalUsers
      from Users u
), DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId
      from PostLinks pl
      join LinkTypes lt on pl.LinkTypeId = lt.Id
     where lt.Name = 'Duplicate'
)
select
    rcte.Id as PostId,
    rcte.PostTypeId,
    rcte.Score,
    rcte.ViewCount,
    u.DisplayName,
    u.Reputation,
    coalesce(ubg_gold.BadgeCount, 0) as GoldBadges,
    coalesce(ubg_silver.BadgeCount, 0) as SilverBadges,
    coalesce(ubg_bronze.BadgeCount, 0) as BronzeBadges,
    lc.CommentId as LatestCommentId,
    lc.CommentUserId,
    lc.CommentDate,
    rcte.Level as DepthLevel,
    case when dup.PostId is not null then 'Has Duplicates'
         else 'No Duplicates'
    end as DuplicateStatus,
    'Score/ViewRatio: ' || round((cast(rcte.Score as numeric) / nullif(rcte.ViewCount,0))::numeric, 4) as ScoreViewRatio,
    rcte.PostRank,
    urw.AvgReputationLast1000Users,
    urw.TotalUsers,
    case when u.WebsiteUrl is not null and position('http' in u.WebsiteUrl) = 1 then 'Valid Website' else 'No Website / Invalid' end as WebsiteStatus,
    substr(coalesce(rcte.AcceptedAnswerId::text, 'None'), 1, 10) as AcceptedAnswerDisplay
  from RecursiveCTE rcte
  join Users u on u.Id = rcte.OwnerUserId
  left join UserBadgeCounts ubg_gold on ubg_gold.UserId = u.Id and ubg_gold.Class = 1
  left join UserBadgeCounts ubg_silver on ubg_silver.UserId = u.Id and ubg_silver.Class = 2
  left join UserBadgeCounts ubg_bronze on ubg_bronze.UserId = u.Id and ubg_bronze.Class = 3
  left join LatestComments lc on lc.PostId = rcte.Id and lc.rn = 1
  left join DuplicateLinks dup on dup.PostId = rcte.Id
  join UserReputationWindow urw on urw.Id = u.Id
 where rcte.Score > 
       (select avg(p2.Score) * 0.8 from Posts p2 where p2.PostTypeId = 1 and p2.OwnerUserId = rcte.OwnerUserId)
   and (substr(u.DisplayName,1,1) in ('A','B','C') or u.Location is not null)
 order by rcte.Level desc, rcte.Score desc
 limit 100;