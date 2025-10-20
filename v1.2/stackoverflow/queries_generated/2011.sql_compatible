with RecursiveBadgeCtes as (
  select
    u.Id as UserId,
    b.Name as BadgeName,
    b.Date,
    cast(row_number() over (partition by u.Id order by b.Date) as integer) as BadgePosition
  from Users u
  join Badges b on b.UserId = u.Id
)
select
  UserId,
  BadgeName,
  Date,
  BadgePosition
from RecursiveBadgeCtes;