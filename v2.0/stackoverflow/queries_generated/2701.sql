-- {"query": "2701.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1529} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.ViewCount,0) as ViewCount,
        coalesce(p.Score,0) as Score,
        case when p.CreationDate >= now() - interval '30 days' then 1 else 0 end as RecentPostFlag,
        row_number() over (partition by t.Id order by p.Score desc nulls last) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
),
UserBadgeStats as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
PostActivityRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc nulls last) as ScoreRank,
        rank() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecencyRank
    from Posts p
    where p.OwnerUserId is not null
),
FilteredPosts as (
    select
        par.*,
        u.Reputation,
        u.DisplayName,
        u.Location,
        u.CreationDate as UserCreationDate,
        u.LastAccessDate,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.TotalBadges,0) as TotalBadges,
        coalesce(ubs.LastBadgeDate, to_timestamp(0)) as LastBadgeDate
    from PostActivityRanks par
    left join Users u on u.Id = par.OwnerUserId
    left join UserBadgeStats ubs on ubs.UserId = par.OwnerUserId
    where par.ScoreRank <= 5 and par.RecencyRank <= 10
),
PostCommentsAgg as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(c.Score) filter (where c.Score > 0) as PositiveCommentScores,
        sum(c.Score) filter (where c.Score <= 0) as NegativeCommentScores,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
ClosedPosts as (
    select distinct ph.PostId, crt.Name as CloseReason, ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name ilike '%closed%'
    left join CloseReasonTypes crt on crt.Id = cast(nullif(ph.Comment,'') as int)
),
PostLinksAggregated as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedPostsCount,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicatePostsCount,
        bool_or(lt.Name = 'Duplicate') as HasDuplicates
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
FinalRankedPosts as (
    select
        fp.*,
        pca.CommentCount,
        pca.PositiveCommentScores,
        pca.NegativeCommentScores,
        pca.LastCommentDate,
        cp.CloseReason,
        cp.CloseDate,
        pla.LinkedPostsCount,
        pla.DuplicatePostsCount,
        pla.HasDuplicates,
        case 
            when cp.CloseReason is not null then 0
            when fp.ScoreRank <= 3 and fp.GoldBadges > 1 then 1
            else 0
        end as FeaturedFlag,
        row_number() over (partition by fp.OwnerUserId order by fp.Score desc nulls last, fp.CreationDate desc) as UserPostRowNum
    from FilteredPosts fp
    left join PostCommentsAgg pca on pca.PostId = fp.Id
    left join ClosedPosts cp on cp.PostId = fp.Id
    left join PostLinksAggregated pla on pla.PostId = fp.Id
)
select 
    frp.Id,
    frp.OwnerUserId,
    frp.DisplayName,
    frp.Location,
    frp.Reputation,
    frp.Score,
    frp.ViewCount,
    frp.Tags,
    frp.GoldBadges,
    frp.SilverBadges,
    frp.BronzeBadges,
    frp.TotalBadges,
    frp.LastBadgeDate,
    frp.CommentCount,
    frp.PositiveCommentScores,
    frp.NegativeCommentScores,
    frp.LastCommentDate,
    frp.CloseReason,
    frp.CloseDate,
    frp.LinkedPostsCount,
    frp.DuplicatePostsCount,
    frp.HasDuplicates,
    frp.FeaturedFlag,
    -- string manipulation with NULL logic and concatenation
    case 
        when frp.Tags is not null and length(frp.Tags) > 0 then 
            concat('Tags: ', replace(substring(frp.Tags, 2, length(frp.Tags) - 2), '><', ', '))
        else 'No Tags'
    end as TagList,
    -- correlated subquery for total answers count by user in last 90 days
    (
        select count(*)
        from Posts p2
        where p2.OwnerUserId = frp.OwnerUserId
          and p2.PostTypeId = 2 -- answers only
          and p2.CreationDate >= now() - interval '90 days'
    ) as RecentAnswerCount,
    -- window function example: cumulative sum of scores by user ordered by creation date
    sum(frp.Score) over (partition by frp.OwnerUserId order by frp.CreationDate rows between unbounded preceding and current row) as CumulativeUserScore,
    -- complicated predicate example: check if user is "active high rep" with badges and recent activity
    (
        case 
            when frp.Reputation > 10000 and frp.TotalBadges >= 10 and frp.LastAccessDate > now() - interval '30 days' then 'ActiveHighRep'
            when frp.Reputation > 500 and frp.TotalBadges >= 3 then 'MidRep'
            else 'LowRep'
        end
    ) as UserCategory
from FinalRankedPosts frp
where frp.UserPostRowNum <= 3 -- limit to top 3 posts per user
order by frp.DisplayName nulls last, frp.Score desc, frp.CreationDate desc
limit 100;