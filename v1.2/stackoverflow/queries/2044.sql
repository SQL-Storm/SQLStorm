with IndexedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.Tags,
        p.OwnerUserId,
        u.Reputation,
        row_number() over (partition by p.PostTypeId order by p.CreationDate desc) as rn
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.Score > (
        select ms.score_avg * 2 from (
            select avg(score) as score_avg from Posts where PostTypeId = p.PostTypeId
        ) as ms
    )
),
PostsLatestEdits as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastEditDate,
        max(case when ph.PostHistoryTypeId in (10) then cast(ph.Comment as integer) end) as CloseReasonLast
    from PostHistory ph
    where ph.PostHistoryTypeId in (4, 5, 6, 10)
    group by ph.PostId
),
UserBadgesGauge as (
    select 
       u.Id as UserId,
       coalesce(sum(case when b.Class = 1 then 1 else 0 end), 0) as GoldBadges,
       coalesce(sum(case when b.Class = 2 then 1 else 0 end), 0) as SilverBadges,
       coalesce(sum(case when b.Class = 3 then 1 else 0 end), 0) as BronzeBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id
)

select distinct
    ip.Id as PostId,
    ip.PostTypeId,
    ip.Score,
    ip.CreationDate,
    ip.Tags,
    ip.OwnerUserId,
    ip.Reputation,
    ip.rn
from IndexedPosts ip
join PostsLatestEdits ple on ip.Id = ple.PostId
left join UserBadgesGauge ubg on ip.OwnerUserId = ubg.UserId
group by
    ip.Id,
    ip.PostTypeId,
    ip.Score,
    ip.CreationDate,
    ip.Tags,
    ip.OwnerUserId,
    ip.Reputation,
    ip.rn,
    ple.PostId,
    ple.LastEditDate,
    ple.CloseReasonLast,
    ubg.UserId,
    ubg.GoldBadges,
    ubg.SilverBadges,
    ubg.BronzeBadges;