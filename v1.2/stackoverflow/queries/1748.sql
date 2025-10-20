with RecursiveDailyPosts as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        cast(p.CreationDate as date) as CreationDay,
        p.PostTypeId,
        Coalesce(u.DisplayName, 'Unknown User') as OwnerDisplayName,
        row_number() over (partition by p.OwnerUserId, cast(p.CreationDate as date) order by p.Score desc, p.Id) as DailyRank,
        p.Score,
        p.CreationDate
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.CreationDate >= cast('2024-10-01' as date) - interval '30 days'
),
WithLastClosing AS (
    select
        ph.PostId,
        max(ph.CreationDate) as LastClosedDate
    from RecursiveDailyPosts ph
    group by ph.PostId
)
select
    r.PostId,
    r.OwnerUserId,
    r.CreationDay,
    r.PostTypeId,
    r.OwnerDisplayName,
    r.DailyRank,
    case
        when r.Score > 10 then 'Hot Topic'
        when r.Score between 5 and 10 then 'Trending'
        else 'Normal'
    end as ScoreTier,
    w.LastClosedDate
from RecursiveDailyPosts r
left join WithLastClosing w on r.PostId = w.PostId
group by
    r.PostId,
    r.OwnerUserId,
    r.CreationDay,
    r.PostTypeId,
    r.OwnerDisplayName,
    r.DailyRank,
    r.Score,
    w.LastClosedDate,
    r.CreationDate;