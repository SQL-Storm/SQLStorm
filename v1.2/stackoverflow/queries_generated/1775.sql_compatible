with RecursiveBenchedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        ul.MaximumScoreOneUser as MaximumScoreOverPosts,
        up.ReputationRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC NULLS LAST) as RecentRank,
        SPLIT_PART(p.Tags, '><', 1) as PrimaryTag,
        sum(case when vb.ScoreEffect < 0 then -vb.ScoreEffect else 0 end) OVER (PARTITION BY p.Id) + COALESCE(p.Score, 0) as CumulativePenaltiesMULT_Weight,
        LEAD(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextPostDatePerUser
    from posts p
    join (
        select
            OwnerUserId,
            max(score) AS MaximumScoreOneUser
        from posts 
        where OwnerUserId is not null 
        group by OwnerUserId
    ) ul on p.OwnerUserId = ul.OwnerUserId 
    join (
        select
            Id,
            NTILE(10) OVER (ORDER BY Reputation DESC) as ReputationRank
        from users
    ) up on p.OwnerUserId = up.Id
    left join (
        select v.PostId, sum(
            case v.VoteTypeId when 2 then 1 when 3 then -1 else 0 end * 100
        ) as ScoreEffect
        from votes v
        group by v.PostId
    ) vb on vb.PostId = p.Id
)
select *
from RecursiveBenchedPosts;