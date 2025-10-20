with recursive RecursivePostParents as (
    select 
        Id as PostId,
        ParentId,
        PostTypeId,
        Title,
        Body,
        CreationDate,
        OwnerUserId
    from posts
    where Id is not null

    union all

    select
        p.Id as PostId,
        p.ParentId,
        p.PostTypeId,
        p.Title,
        p.Body,
        p.CreationDate,
        p.OwnerUserId
    from posts p
    join RecursivePostParents r on p.ParentId = r.PostId
)
select
    r.PostId,
    r.ParentId,
    r.PostTypeId,
    r.Title,
    r.Body,
    r.CreationDate,
    r.OwnerUserId,
    count(*) over () as total_rows
from RecursivePostParents r
group by
    r.PostId,
    r.ParentId,
    r.PostTypeId,
    r.Title,
    r.Body,
    r.CreationDate,
    r.OwnerUserId;