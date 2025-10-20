with recursive PostsTree as (
  select
    p.Id,
    p.PostTypeId,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.CreationDate,
    0 as Level,
    p.ParentId
  from Posts p
  where p.PostTypeId = 1

  union all

  select
    c.Id,
    c.PostTypeId,
    c.Title,
    c.OwnerUserId,
    c.Score,
    c.CreationDate,
    pt.Level + 1,
    c.ParentId
  from Posts c
  inner join PostsTree pt on c.ParentId = pt.Id
  where c.PostTypeId <> 1
),
MedalsUserRanks as (
  select
    b.UserId,
    b.Class,
    count(*) as badge_count
  from Badges b
  where b.Date > (cast('2024-10-01' as date) - interval '1' year)
  group by b.UserId, b.Class
),
UserTotalMedals as (
  select
    mur.UserId,
    mur.Class,
    sum(mur.badge_count) as total_badges
  from MedalsUserRanks mur
  group by mur.UserId, mur.Class
)
select
  pt.Id,
  pt.PostTypeId,
  pt.Title,
  pt.OwnerUserId,
  pt.Score,
  pt.CreationDate,
  pt.Level,
  pt.ParentId,
  coalesce(utm.total_badges, 0) as total_badges
from PostsTree pt
left join UserTotalMedals utm
  on pt.OwnerUserId = utm.UserId
group by
  pt.Id,
  pt.PostTypeId,
  pt.Title,
  pt.OwnerUserId,
  pt.Score,
  pt.CreationDate,
  pt.Level,
  pt.ParentId,
  utm.total_badges
order by
  pt.CreationDate;