-- {"query": "1158.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1168} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as UserLocation,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) as BadgeCount,
        sum(coalesce(p.Score,0)) as TotalPostScore,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.UpVotes, u.DownVotes
),

RankedPosts as (
    select 
        p.Id, 
        p.PostTypeId, 
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc, p.CreationDate asc) as TypeRank,
        dense_rank() over (order by p.Score desc) as OverallScoreRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2)
),

DuplicateLinkInfo as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p.Title as RelatedPostTitle,
        p.Score as RelatedPostScore
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p on p.Id = pl.RelatedPostId
    where lt.Name = 'Duplicate'
),

PostWithCloseReasons as (
    select 
        ph.PostId,
        string_agg(distinct crt.Name, ', ') as CloseReasons,
        min(ph.CreationDate) as FirstCloseDate,
        max(ph.CreationDate) as LastCloseDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes crt on crt.Id = ph.Comment::int
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId
),

UserBadgeSummary as (
    select 
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadgeNames
    from Badges b
    group by b.UserId
)

select 
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    rua.UserLocation,
    rua.QuestionCount,
    rua.AnswerCount,
    rua.CommentCount,
    rua.BadgeCount,
    coalesce(ub.GoldBadges,0) as GoldBadges,
    coalesce(ub.SilverBadges,0) as SilverBadges,
    coalesce(ub.BronzeBadges,0) as BronzeBadges,
    ub.DistinctBadgeNames,
    rp.Id as TopQuestionId,
    rp.Title as TopQuestionTitle,
    rp.Score as TopQuestionScore,
    rp.ViewCount as TopQuestionViews,
    rp.Tags as TopQuestionTags,
    dli.RelatedPostId as DuplicateOfPostId,
    dli.RelatedPostTitle as DuplicateOfPostTitle,
    dli.RelatedPostScore as DuplicateOfPostScore,
    pcr.CloseReasons,
    pcr.FirstCloseDate,
    pcr.LastCloseDate,
    -- complex calculation: user engagement score normalized with log and window function for rank partitioned by location
    log(1 + rua.QuestionCount * 2 + rua.AnswerCount * 3 + rua.CommentCount) / nullif(rank() over (partition by rua.UserLocation order by rua.Reputation desc),0) as EngagementScoreNormalized
from RecursiveUserActivity rua
left join UserBadgeSummary ub on ub.UserId = rua.UserId
left join lateral (
    select rp.*
    from RankedPosts rp
    where rp.OwnerUserId = rua.UserId and rp.PostTypeId = 1
    order by rp.Score desc nulls last, rp.ViewCount desc nulls last
    limit 1
) rp on true
left join DuplicateLinkInfo dli on dli.PostId = rp.Id
left join PostWithCloseReasons pcr on pcr.PostId = rp.Id
where rua.Reputation > (
    select avg(Reputation)*1.5 from Users
) 
and (rua.LastAccessDate > current_timestamp - interval '180 days')
and (
    pcr.CloseReasons is null or pcr.CloseReasons not like '%Duplicate%'
)
order by EngagementScoreNormalized desc
limit 100;