with RankedPosts as (
    select 
        p.Id, 
        p.PostTypeId, 
        p.OwnerUserId, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.Title, 
        p.Tags,
        row_number() over (partition by coalesce(p.OwnerUserId, -1) order by p.Score desc, p.CreationDate asc) as rn,
        lag(p.Score) over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate asc) as prev_score
    from Posts p
)
select
    rp.Id,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Title,
    rp.Tags,
    rp.rn,
    rp.prev_score
from RankedPosts rp
where rp.rn = 1;