with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.AnswerCount,
        p.ViewCount,
        p.Tags,
        row_number() over(partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc, p.CreationDate) as rn,
        rank() over(partition by p.PostTypeId order by p.CreationDate) as c_rnk
    from
        Posts p
    where
        p.PostTypeId in (1,2)
        and p.CreationDate > (cast('2024-10-01' as date) - interval '365' day)
),
UserBadgeCounts as (
    select 
        b.UserId, 
        sum(case when b.Class = 1 then 1 else 0 end) as Gold,
        sum(case when b.Class = 2 then 1 else 0 end) as Silver,
        sum(case when b.Class = 3 then 1 else 0 end) as Bronze,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
TopRankedPosts as (
    select
        rp.Id,
        rp.PostTypeId,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.Score,
        rp.AnswerCount,
        rp.ViewCount,
        rp.Tags,
        rp.rn,
        rp.c_rnk,
        ubc.Gold,
        ubc.Silver,
        ubc.Bronze,
        ubc.TotalBadges,
        u.DisplayName,
        u.Reputation,
        coalesce(length(p.Title),0) as TitleLength
    from RankedPosts rp
    left join UserBadgeCounts ubc on ubc.UserId = rp.OwnerUserId
    left join Users u on u.Id = rp.OwnerUserId
    left join Posts p on p.Id = rp.Id
    where rp.rn = 1
)
select
    trp.Id,
    trp.PostTypeId,
    trp.CreationDate,
    trp.OwnerUserId,
    trp.Score,
    trp.AnswerCount,
    trp.ViewCount,
    trp.Tags,
    trp.rn,
    trp.c_rnk,
    trp.Gold,
    trp.Silver,
    trp.Bronze,
    trp.TotalBadges,
    trp.DisplayName,
    trp.Reputation,
    trp.TitleLength
from TopRankedPosts trp
order by trp.Score desc, trp.ViewCount desc, trp.CreationDate;