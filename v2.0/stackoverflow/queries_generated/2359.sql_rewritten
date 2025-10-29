-- {"query": "2359.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1170} 
with recursive TagHierarchy as (
    select Id, TagName, Count, WikiPostId, 0 as Level
    from Tags
    where TagName in ('sql', 'query', 'performance')
    union all
    select t.Id, t.TagName, t.Count, t.WikiPostId, th.Level + 1
    from Tags t
    join TagHierarchy th on t.ExcerptPostId = th.WikiPostId
    where t.TagName is not null and th.Level < 2
),
PostsWithTagHierarchy as (
    select p.*, th.Level as TagHierarchyLevel,
           coalesce(p.ViewCount,0)+coalesce(p.Score*10,0) + coalesce(p.FavoriteCount*20,0) as PopularityScore,
           row_number() over (partition by p.OwnerUserId order by coalesce(p.ViewCount,0)+coalesce(p.Score*10,0) desc) as UserPostRank
    from Posts p
    left join TagHierarchy th on p.Tags like concat('%<', th.TagName, '>%')
    where p.PostTypeId in (1,2)
),
UserBadgeSummary as (
    select b.UserId,
           sum(case when b.Class=1 then 1 else 0 end) as GoldBadges,
           sum(case when b.Class=2 then 1 else 0 end) as SilverBadges,
           sum(case when b.Class=3 then 1 else 0 end) as BronzeBadges,
           count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
UserActivity as (
    select u.Id as UserId, u.DisplayName,
           count(distinct case when p.PostTypeId=1 then p.Id end) as NumQuestions,
           count(distinct case when p.PostTypeId=2 then p.Id end) as NumAnswers,
           count(distinct c.Id) as NumComments,
           max(p.LastActivityDate) as LastPostActivity,
           max(c.CreationDate) as LastCommentActivity,
           greatest(max(p.LastActivityDate), max(c.CreationDate)) as LastActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
),
RankedUserActivity as (
    select ua.*,
           rank() over (order by ua.NumAnswers desc, ua.NumQuestions desc, ua.NumComments desc) as ActivityRank
    from UserActivity ua
),
UserPostVotes as (
    select p.OwnerUserId as UserId,
           sum(case when v.VoteTypeId=2 then 1 else 0 end) as UpVotesReceived,
           sum(case when v.VoteTypeId=3 then 1 else 0 end) as DownVotesReceived,
           sum(case when v.VoteTypeId=5 then 1 else 0 end) as FavoriteVotesReceived
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.OwnerUserId
),
DuplicateLinkCounts as (
    select pl.PostId,
           count(*) filter (where pl.LinkTypeId=3) as NumDuplicates,
           count(*) filter (where pl.LinkTypeId=1) as NumLinkedPosts
    from PostLinks pl
    group by pl.PostId
)
select p.Id as PostId,
       p.Title,
       p.CreationDate,
       p.Score,
       p.ViewCount,
       u.DisplayName as OwnerName,
       coalesce(ub.GoldBadges,0) as OwnerGoldBadges,
       coalesce(ub.SilverBadges,0) as OwnerSilverBadges,
       coalesce(ub.BronzeBadges,0) as OwnerBronzeBadges,
       p.Tags,
       p.AnswerCount,
       pwth.TagHierarchyLevel,
       pwth.PopularityScore,
       plc.NumDuplicates,
       case when plc.NumDuplicates > 0 then 'Has duplicates' else 'No duplicates' end as DuplicateStatus,
       -- Window function to show avg score of posts with same TagHierarchyLevel
       avg(pwth.Score) over (partition by pwth.TagHierarchyLevel) as AvgScoreForTagLevel,
       -- Correlated subquery: count comments on this post with score > 0
       (select count(*) from Comments c where c.PostId = p.Id and (c.Score is not null and c.Score > 0)) as PositiveCommentsCount,
       -- Complex predicate with NULL logic to check if post is 'Hot'
       case when (p.Score > 5 or p.ViewCount > 1000) and (p.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') then 1 else 0 end as IsHot,
       -- String expression: concat first 20 chars of body with '...'
       concat(left(p.Body, 20), '...') as BodyPreview
from PostsWithTagHierarchy pwth
join Posts p on p.Id = pwth.Id
left join Users u on u.Id = p.OwnerUserId
left join UserBadgeSummary ub on ub.UserId = u.Id
left join DuplicateLinkCounts plc on plc.PostId = p.Id
where pwth.PopularityScore > (
    select avg(coalesce(ViewCount,0)+coalesce(Score*10,0)+coalesce(FavoriteCount*20,0)) from Posts where PostTypeId=1
)
and p.ClosedDate is null
order by pwth.PopularityScore desc, p.CreationDate desc
limit 100;