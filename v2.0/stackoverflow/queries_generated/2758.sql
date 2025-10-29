-- {"query": "2758.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 982} 
with RecursiveTagTree as (
  select t.Id, t.TagName, 1 as Level, array[t.TagName] as AncestorPath
  from Tags t
  where t.IsModeratorOnly = 0 and t.IsRequired = 0
  union all
  select t.Id, t.TagName, r.Level + 1, r.AncestorPath || t.TagName
  from Tags t
    join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    join RecursiveTagTree r on array_position(r.AncestorPath, t.TagName) is null
  where t.IsModeratorOnly = 0 and t.IsRequired = 0
    and r.Level < 3
),
UserBadgeCount as (
  select u.Id as UserId, u.DisplayName,
     count(b.Id) filter (where b.Class=1) as GoldBadges,
     count(b.Id) filter (where b.Class=2) as SilverBadges,
     count(b.Id) filter (where b.Class=3) as BronzeBadges,
     sum(coalesce(b.Date < u.CreationDate + interval '1 year' and 1, 0)) as BadgesFirstYear
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName
),
TopPostsWithComments as (
  select p.Id, p.Title, p.PostTypeId, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount,
     count(c.Id) as CommentCount,
     row_number() over (partition by p.PostTypeId order by p.Score desc NULLS LAST, p.ViewCount desc) as RankByScore
  from Posts p
  left join Comments c on c.PostId = p.Id
  where p.CreationDate >= current_date - interval '1 year'
  group by p.Id, p.Title, p.PostTypeId, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount
),
UserRecentActivity as (
  select u.Id, u.DisplayName,
     max(p.LastActivityDate) as LastPostActivity,
     max(c.CreationDate) as LastCommentDate,
     max(ph.CreationDate) as LastHistoryEdit
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  left join PostHistory ph on ph.UserId = u.Id
  group by u.Id, u.DisplayName
)
select
  u.DisplayName,
  u.Reputation,
  ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
  ub.BadgesFirstYear,
  ua.LastPostActivity,
  ua.LastCommentDate,
  ua.LastHistoryEdit,
  tp.Title as TopQuestionTitle,
  tp.Score as TopQuestionScore,
  tp.ViewCount as TopQuestionViews,
  tp.CommentCount as TopQuestionCommentCount,
  coalesce(pl.NumDuplicates, 0) as NumDuplicateLinks,
  coalesce(avgVotes.UpVotesAvg, 0) as AvgUpVotesPerAnswer
from Users u
inner join UserBadgeCount ub on ub.UserId = u.Id
left join UserRecentActivity ua on ua.Id = u.Id
left join lateral (
   select p.Title, p.Score, p.ViewCount, p.CommentCount
   from TopPostsWithComments p
   where p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.RankByScore = 1
   order by p.Score desc nulls last limit 1
) tp on true
left join (
  select pl.PostId, count(*) as NumDuplicates
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
  group by pl.PostId
) pl on pl.PostId = tp.Id
left join lateral (
  select avg(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesAvg
  from Posts a
  left join Votes v on v.PostId = a.Id
  where a.PostTypeId = 2 and a.OwnerUserId = u.Id
) avgVotes on true
where u.Reputation > 1000
  and (
    (ub.GoldBadges > 0 and ub.BadgesFirstYear >= 1)
    or (ub.SilverBadges > 3)
    or (ua.LastPostActivity > current_date - interval '6 months')
  )
order by ub.GoldBadges desc, ua.LastPostActivity desc nulls last
limit 100;