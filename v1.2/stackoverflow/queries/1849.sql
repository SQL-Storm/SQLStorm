with recursive RecursivePosts as (
    select p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.Tags,
           1 as Level,
           cast(p.Id as varchar) as Path
      from Posts p
     where p.PostTypeId = 1
       and p.CreationDate >= (cast('2024-10-01' as date) - interval '2 years')

 union all

    select c.Id, c.PostTypeId, c.CreationDate, c.Score, c.ViewCount, c.OwnerUserId, c.Tags,
           rp.Level + 1 as Level,
           rp.Path || '->' || cast(c.Id as varchar) as Path
      from Posts c
      join RecursivePosts rp on c.ParentId = rp.Id
      where rp.Level < 5
)
, UserStats AS (
   select 
       U.Id,
       U.DisplayName,
       U.Reputation,
       U.CreationDate
   from Users U
)
select rp.Id,
       rp.PostTypeId,
       rp.CreationDate,
       rp.Score,
       rp.ViewCount,
       rp.OwnerUserId,
       rp.Tags,
       rp.Level,
       rp.Path,
       us.Id as UserId,
       us.DisplayName,
       us.Reputation,
       us.CreationDate as UserCreationDate
from RecursivePosts rp
left join UserStats us on rp.OwnerUserId = us.Id
group by
    rp.Id,
    rp.PostTypeId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.Tags,
    rp.Level,
    rp.Path,
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.CreationDate;