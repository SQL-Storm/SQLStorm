with RecencyFilteredUsers as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        count(distinct b.Id) as BadgeCount,
        max(b.Date) as LatestBadgeDate,
        case 
            when max(b.Date) is null then cast('1900-01-01' as timestamp)
            else max(b.Date)
        end as ResolvedLatestBadgeDate
    from Users u
    left join Badges b
        on u.Id = b.UserId
        and b.Date > cast('2024-10-01' as date) - interval '1 year'
    group by
        u.Id,
        u.DisplayName,
        u.CreationDate,
        u.Reputation
)
select *
from RecencyFilteredUsers;