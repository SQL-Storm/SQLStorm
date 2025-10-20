with RankedPosts as (
    select
        p.Id,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Body,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn
    from Posts p
    where p.PostTypeId in (1, 2)
)
select
    rp.Id,
    rp.OwnerUserId,
    rp.ParentId,
    rp.PostTypeId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Body,
    rp.Title,
    rp.Tags,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount
from RankedPosts rp
where rp.rn = 1;