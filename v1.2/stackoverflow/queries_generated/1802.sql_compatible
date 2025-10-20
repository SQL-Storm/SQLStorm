with QualifiedPosts as (
  select 
    p.Id,
    p.PostTypeId,
    p.ParentId,
    p.OwnerUserId,
    p.Title,
    p.ViewCount,
    p.Score,
    p.Tags,
    case 
      when p.Score >= 10 and p.ViewCount >= 1000 then 'HighEngagement'
      when p.Score >= 0 then 'ModerateEngagement'
      else 'LowEngagement'
    end as EngagementLevel
  from Posts p
  where p.PostTypeId in (1, 2)
    and p.CreationDate >= date '2020-01-01'
),
UserStats as (
  select 
    u.Id,
    u.DisplayName,
    u.Reputation,
    count(case when b.Class = 1 then 1 end) as GoldBadges,
    count(case when b.Class = 2 then 1 end) as SilverBadges,
    count(case when b.Class = 3 then 1 end) as BronzeBadges,
    lag(u.Reputation) over (order by u.Reputation desc) as PrevRep,
    lead(u.Reputation) over (order by u.Reputation desc) as NextRep,
    bool_or(coalesce(nullif(u.Location, ''), 'unknown') not like '%test%') as IsValidLocation,
    count(p.Id) as PostsAuthored
  from Users u
  left join Badges b on b.UserId = u.Id
  left join Posts p on p.OwnerUserId = u.Id and p.CreationDate >= date '2020-01-01'
  group by u.Id, u.DisplayName, u.Reputation, u.Location
  having count(p.Id) > 5
),
RndRecentComments as (
  select 
    c.Id,
    c.PostId,
    c.Text,
    c.UserId
  from Comments c
  where c.CreationDate >= cast('2024-10-01' as date) - interval '30' day
)
select
  qp.Id as PostId,
  qp.PostTypeId,
  qp.ParentId,
  qp.OwnerUserId,
  qp.Title,
  qp.ViewCount,
  qp.Score,
  qp.Tags,
  qp.EngagementLevel,
  us.Id as UserId,
  us.DisplayName,
  us.Reputation,
  us.GoldBadges,
  us.SilverBadges,
  us.BronzeBadges,
  us.PrevRep,
  us.NextRep,
  us.IsValidLocation,
  us.PostsAuthored,
  rc.Id as CommentId,
  rc.Text as CommentText,
  rc.UserId as CommentUserId
from QualifiedPosts qp
left join UserStats us on us.Id = qp.OwnerUserId
left join RndRecentComments rc on rc.PostId = qp.Id
group by
  qp.Id,
  qp.PostTypeId,
  qp.ParentId,
  qp.OwnerUserId,
  qp.Title,
  qp.ViewCount,
  qp.Score,
  qp.Tags,
  qp.EngagementLevel,
  us.Id,
  us.DisplayName,
  us.Reputation,
  us.GoldBadges,
  us.SilverBadges,
  us.BronzeBadges,
  us.PrevRep,
  us.NextRep,
  us.IsValidLocation,
  us.PostsAuthored,
  rc.Id,
  rc.PostId,
  rc.Text,
  rc.UserId;