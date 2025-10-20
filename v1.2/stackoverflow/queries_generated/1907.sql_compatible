with RankedPosts as (
  select 
    p.Id,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    u.DisplayName as Owner,
    p.Title,
    dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.CreationDate) as ScoreRank,
    count(c.Id) over (partition by p.Id) as CommentCount,
    row_number() over (partition by p.ParentId order by p.CreationDate) as RowNum
  from posts p
  left join users u on p.OwnerUserId = u.Id
  left join comments c on c.PostId = p.Id
)
select
  Id,
  PostTypeId,
  CreationDate,
  Score,
  Owner,
  Title,
  ScoreRank,
  CommentCount,
  RowNum
from RankedPosts;