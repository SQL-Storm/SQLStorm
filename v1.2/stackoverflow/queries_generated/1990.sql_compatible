with RecursiveFilter as (
    select 
        p.Id,
        p.PostTypeId,
        regexp_replace(p.Tags, '[<>]', '{}') || COALESCE(NULLIF(p.Tags, ''), '{}') as modtags,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) as rn
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1, 2)
      and p.Score > 5
)
select *
from RecursiveFilter;