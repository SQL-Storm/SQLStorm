with recursive UserRankCTE as (
    select u.Id as UserId,
           u.DisplayName,
           u.Reputation,
           RANK() over (order by u.Reputation desc, u.CreationDate asc) as UserReputationRank
      from Users u
    where u.DisplayName is not null
  ),
  TopBadgers as (
    select b.UserId,
           count(*) as BadgeCount,
           sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
           sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
           sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
      from Badges b
     group by b.UserId
    having count(*) > 10
  ),
  PopularTags as (
    select array_agg(distinct '<' || t.TagName || '>') as TagPatterns
      from Tags t
     where t.Count > 10000
  )
select u.UserId,
       u.DisplayName,
       u.Reputation,
       u.UserReputationRank,
       tb.BadgeCount,
       tb.GoldBadges,
       tb.SilverBadges,
       tb.BronzeBadges,
       pt.TagPatterns
  from UserRankCTE u
  left join TopBadgers tb
    on u.UserId = tb.UserId
  left join PopularTags pt
    on true
 order by u.UserReputationRank;