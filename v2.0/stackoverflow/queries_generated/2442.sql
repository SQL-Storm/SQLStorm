-- {"query": "2442.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1194} 
with RecursivePostCounts as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        1 as BaseCount
    from Posts p
    where p.PostTypeId = 1 -- questions only
    union all
    select
        a.Id,
        a.PostTypeId,
        a.CreationDate,
        a.Score,
        a.ViewCount,
        a.Tags,
        a.OwnerUserId,
        a.AcceptedAnswerId,
        rpc.BaseCount + 1
    from Posts a
    join RecursivePostCounts rpc on a.ParentId = rpc.Id
    where a.PostTypeId = 2 -- answers only
),
UserBadgesCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        coalesce(sum(b.Class),0) as BadgeScore
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
TopUsersRecentActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        row_number() over (order by u.Reputation desc nulls last, u.LastAccessDate desc) as Rank
    from Users u
    left join UserBadgesCounts ub on u.Id = ub.UserId
    where u.Reputation > 5000 and u.LastAccessDate > (current_date - interval '365 days')
),
PostLinkDetails as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Score as PostScore,
        p2.Score as RelatedPostScore,
        p1.Tags as PostTags,
        p2.Tags as RelatedPostTags
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    join Posts p1 on pl.PostId = p1.Id
    join Posts p2 on pl.RelatedPostId = p2.Id
),
ComplexPostStats as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        case 
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Accepted'
            else 'Open'
        end as PostStatus,
        -- count of distinct users who commented on post
        (select count(distinct c.UserId) from Comments c where c.PostId = p.Id and c.UserId is not null) as CommentingUsersCount,
        -- average score of answers for this question
        (select avg(a.Score) from Posts a where a.ParentId = p.Id and a.PostTypeId = 2) as AvgAnswerScore,
        -- max score for answers for this question
        (select max(a.Score) from Posts a where a.ParentId = p.Id and a.PostTypeId = 2) as MaxAnswerScore,
        -- risk flag expression involving score, views and recency
        case 
            when p.Score < 0 and p.ViewCount < 100 and p.CreationDate < (current_date - interval '2 years') then 1
            else 0
        end as RiskFlag
    from Posts p
    where p.PostTypeId = 1
),
RankedPostsWithWindow as (
    select 
        cps.*,
        row_number() over (partition by cps.PostStatus order by cps.Score desc nulls last, cps.ViewCount desc nulls last) as RankWithinStatus,
        dense_rank() over (order by cps.FavoriteCount desc nulls last) as FavoriteRank,
        ntile(4) over (order by cps.AvgAnswerScore desc nulls last) as QuartileByAvgAnswerScore
    from ComplexPostStats cps
),
FinalOutput as (
    select 
        tp.RankWithinStatus,
        tp.Title,
        tp.PostStatus,
        tp.Score,
        tp.ViewCount,
        tp.AnswerCount,
        tp.CommentCount,
        tp.FavoriteCount,
        tp.CommentingUsersCount,
        coalesce(tp.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(tp.MaxAnswerScore,0) as MaxAnswerScore,
        tp.RiskFlag,
        ru.DisplayName as OwnerUserName,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        pl.LinkTypeName,
        pl.RelatedPostId,
        pl.RelatedPostScore,
        pl.RelatedPostTags
    from RankedPostsWithWindow tp
    left join Posts p on p.Id = tp.Id
    left join Users ru on ru.Id = p.OwnerUserId
    left join UserBadgesCounts ub on ub.UserId = ru.Id
    left join PostLinkDetails pl on pl.PostId = tp.Id
    where tp.RankWithinStatus <= 10
)
select *
from FinalOutput
order by PostStatus, RankWithinStatus, FavoriteRank desc nulls last, AvgAnswerScore desc nulls last
limit 100;