with RecursiveUserBadgeCte as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        cast(1 as integer) as BadgeChainCnt,
        lead(b.Date) over (partition by b.UserId order by b.Date) as NextBadgeDate,
        b.Date as BadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
)
select
    r.UserId,
    r.DisplayName,
    r.BadgeName,
    r.BadgeClass,
    r.BadgeChainCnt,
    r.NextBadgeDate,
    r.BadgeDate
from RecursiveUserBadgeCte r
;