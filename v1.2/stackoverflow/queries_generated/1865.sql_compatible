with RecentQuestions as (
    select p.Id, p.Title, p.OwnerUserId, p.CreationDate,
      row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rq_rank
    from Posts p
    where p.PostTypeId = 1 -- questions
      and p.CreationDate >= timestamp '2024-10-01 12:34:56' - interval '90' day
), TopUsers as (
    select u.Id, u.DisplayName, u.Reputation, u.CreationDate
    from Users u
    where u.Reputation >= 10000
      and u.CreationDate >= timestamp '2024-10-01 12:34:56' - interval '3' year
), UserBadgeExplosion as (
    select b.UserId, b.Name as BadgeName, 
      case when b.Class = 1 then 'Gold'
           when b.Class = 2 then 'Silver'
           when b.Class = 3 then 'Bronze'
           else 'Unknown'
      end as BadgeClass,
      dense_rank() over (partition by b.UserId order by b.Class, b.Name) as rinsed_rank
    from Badges b 
    inner join Users u on b.UserId = u.Id
    inner join TopUsers bu on b.UserId = bu.Id
), UserRecentBadges as (
    select ube.UserId, ube.BadgeName, ube.BadgeClass, ube.rinsed_rank
    from UserBadgeExplosion ube
    where ube.rinsed_rank <= 5
)
select tu.Id as UserId,
       tu.DisplayName,
       tu.Reputation,
       tu.CreationDate as UserCreationDate,
       rq.Id as RecentQuestionId,
       rq.Title as RecentQuestionTitle,
       rq.CreationDate as RecentQuestionCreationDate,
       rq.rq_rank,
       urb.BadgeName,
       urb.BadgeClass,
       urb.rinsed_rank
from TopUsers tu
left join RecentQuestions rq
  on rq.OwnerUserId = tu.Id and rq.rq_rank <= 3
left join UserRecentBadges urb
  on urb.UserId = tu.Id
group by
  tu.Id,
  tu.DisplayName,
  tu.Reputation,
  tu.CreationDate,
  rq.Id,
  rq.Title,
  rq.CreationDate,
  rq.rq_rank,
  urb.BadgeName,
  urb.BadgeClass,
  urb.rinsed_rank
order by tu.Reputation desc, tu.Id, rq.rq_rank;