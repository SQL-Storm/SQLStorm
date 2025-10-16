-- {"query": "702.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1521} 
with RecursiveCTE as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        u.Reputation,
        u.DisplayName,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn,
        1 as Level
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2) -- Questions and Answers
    union all
    select
        p2.Id,
        p2.PostTypeId,
        p2.OwnerUserId,
        p2.Score,
        p2.ViewCount,
        p2.CreationDate,
        p2.Tags,
        u2.Reputation,
        u2.DisplayName,
        r.Level + 1,
        r.Level + 1
    from Posts p2
    inner join RecursiveCTE r on p2.ParentId = r.PostId
    left join Users u2 on p2.OwnerUserId = u2.Id
    where p2.PostTypeId = 2
    and r.Level < 3
),
RankedPosts as (
    select
        PostId,
        PostTypeId,
        OwnerUserId,
        Score,
        ViewCount,
        CreationDate,
        Tags,
        Reputation,
        DisplayName,
        Level,
        dense_rank() over (partition by OwnerUserId order by Score desc, ViewCount desc) as ScoreRank
    from RecursiveCTE
),
FilteredPosts as (
    select *
    from RankedPosts
    where ScoreRank <= 5
),
PostBadgesAgg as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    where b.Class in (1, 2, 3)
    group by b.UserId, b.Class
),
UserBadgeSummary as (
    select
        UserId,
        coalesce(sum(case when Class = 1 then BadgeCount end),0) as GoldBadges,
        coalesce(sum(case when Class = 2 then BadgeCount end),0) as SilverBadges,
        coalesce(sum(case when Class = 3 then BadgeCount end),0) as BronzeBadges
    from PostBadgesAgg
    group by UserId
),
PostCommentsCount as (
    select
        c.PostId,
        count(*) as TotalComments,
        count(case when c.UserId is null then 1 end) as AnonymousComments,
        count(case when c.UserId is not null then 1 end) as RegisteredComments
    from Comments c
    group by c.PostId
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseVotes
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
PostLinkAggregates as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount
    from PostLinks pl
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
)
select 
    fp.PostId,
    fp.PostTypeId,
    fp.OwnerUserId,
    u.DisplayName as OwnerName,
    fp.Score,
    fp.ViewCount,
    fp.CreationDate,
    fp.Tags,
    fp.Reputation,
    coalesce(ubs.GoldBadges,0) as GoldBadges,
    coalesce(ubs.SilverBadges,0) as SilverBadges,
    coalesce(ubs.BronzeBadges,0) as BronzeBadges,
    coalesce(pc.TotalComments,0) as TotalComments,
    coalesce(pc.AnonymousComments,0) as AnonymousComments,
    coalesce(pc.RegisteredComments,0) as RegisteredComments,
    coalesce(pcr.CloseVotes,0) as CloseVotes,
    coalesce(plag.LinkedCount,0) as LinkedPosts,
    coalesce(plag.DuplicateCount,0) as DuplicatePosts,
    case 
        when fp.Score > 100 and fp.ViewCount > 10000 then 'High Impact'
        when fp.Score between 50 and 100 and fp.ViewCount between 5000 and 10000 then 'Medium Impact'
        else 'Low Impact'
    end as ImpactCategory,
    substring(fp.Tags from '<([^>]+)>') as FirstTag,
    (select count(*) from Posts p3 where p3.OwnerUserId = fp.OwnerUserId and p3.PostTypeId = 1 and p3.CreationDate < fp.CreationDate) as PreviousQuestionsCount,
    (select avg(Score) from Posts p4 where p4.OwnerUserId = fp.OwnerUserId and p4.PostTypeId = 2 and p4.CreationDate < fp.CreationDate) as AvgAnswerScoreBefore,
    row_number() over (partition by fp.OwnerUserId order by fp.CreationDate) as UserPostSequence,
    lag(fp.Score,1,0) over (partition by fp.OwnerUserId order by fp.CreationDate) as PrevPostScore,
    lead(fp.Score,1,0) over (partition by fp.OwnerUserId order by fp.CreationDate) as NextPostScore
from FilteredPosts fp
left join Users u on u.Id = fp.OwnerUserId
left join UserBadgeSummary ubs on ubs.UserId = fp.OwnerUserId
left join PostCommentsCount pc on pc.PostId = fp.PostId
left join PostCloseReasons pcr on pcr.PostId = fp.PostId
left join PostLinkAggregates plag on plag.PostId = fp.PostId
where fp.Level = 1
and (fp.Tags is not null and fp.Tags like '%<sql>%')
union
select 
    p.Id as PostId,
    p.PostTypeId,
    p.OwnerUserId,
    u.DisplayName as OwnerName,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Tags,
    u.Reputation,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    0 as TotalComments,
    0 as AnonymousComments,
    0 as RegisteredComments,
    0 as CloseVotes,
    0 as LinkedPosts,
    0 as DuplicatePosts,
    'No Data' as ImpactCategory,
    null as FirstTag,
    0 as PreviousQuestionsCount,
    null as AvgAnswerScoreBefore,
    0 as UserPostSequence,
    0 as PrevPostScore,
    0 as NextPostScore
from Posts p
left join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 1
and p.Tags is null
order by OwnerUserId, CreationDate desc
limit 100;