with RecursiveConversation as (
  select
    p.Id as PostId,
    p.ParentId,
    u.DisplayName as OwnerName,
    p.Title,
    ROW_NUMBER() OVER (ORDER BY p.Id) as rn
  from posts p
  left join users u on p.OwnerUserId = u.Id
  where p.PostTypeId = 1
)
select
  rc.PostId,
  rc.ParentId,
  rc.OwnerName,
  rc.Title,
  rc.rn
from RecursiveConversation rc
order by rc.PostId;