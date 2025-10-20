with
RecursiveUserBadges as (
    select
        u.Id as UserId,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc, b.Class desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
),
FilteredPosts as (
    select 
        p.Id,
        p.PostTypeId,
        coalesce(p.Score,0) as Score,
        p.CreationDate,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        ln(nullif(p.ViewCount,0)) * 10 + coalesce(p.Score,0) * 3 + coalesce(p.FavoriteCount,0) * 5 as posWeight
    from Posts p
    where p.PostTypeId in (1,2)
      and p.CreationDate >= cast('2024-10-01' as date) - interval '365 days'
      and coalesce(p.Score,0) >= 0
)
select
    fp.Id,
    fp.PostTypeId,
    fp.Score,
    fp.CreationDate,
    fp.OwnerUserId,
    fp.AcceptedAnswerId,
    fp.posWeight,
    rub.BadgeName,
    rub.Class,
    rub.BadgeRank
from FilteredPosts fp
left join RecursiveUserBadges rub
    on fp.OwnerUserId = rub.UserId and rub.BadgeRank = 1
order by fp.posWeight desc, fp.CreationDate desc;