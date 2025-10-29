-- {"query": "2567.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1393} 
with RecursiveUserActivity as (
  select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    coalesce(u.Location, 'Unknown') as Location,
    count(distinct ph.Id) as EditCount,
    count(distinct p.Id) as PostCount,
    count(distinct c.Id) as CommentCount,
    row_number() over (partition by coalesce(u.Location, 'Unknown') order by u.Reputation desc) as LocationRank
  from Users u
  left join PostHistory ph on ph.UserId = u.Id
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, coalesce(u.Location, 'Unknown')
), 
UserBadgeSummary as (
  select 
    b.UserId,
    count(*) as BadgeCount,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    string_agg(distinct b.Name, ', ' order by b.Name) as BadgeNames
  from Badges b
  group by b.UserId
), 
TopPosts as (
  select 
    p.Id,
    p.Title,
    p.PostTypeId,
    pt.Name as PostTypeName,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Tags,
    u.DisplayName as OwnerName,
    u.Reputation as OwnerReputation,
    row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as PostRank
  from Posts p
  left join PostTypes pt on pt.Id = p.PostTypeId
  left join Users u on u.Id = p.OwnerUserId
  where p.PostTypeId in (1, 2) and p.Score is not null
),
DuplicateLinkCounts as (
  select 
    pl.PostId,
    count(*) filter (where lt.Name = 'Duplicate') as DuplicateLinks
  from PostLinks pl
  left join LinkTypes lt on lt.Id = pl.LinkTypeId
  group by pl.PostId
),
UserComplexMetrics as (
  select 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.EditCount,
    ua.PostCount,
    ua.CommentCount,
    ub.BadgeCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    case 
      when ua.PostCount > 0 then round(cast(ua.EditCount as numeric)/ua.PostCount, 2) 
      else null 
    end as EditsPerPost,
    (select count(*) from Votes v2 where v2.UserId = ua.UserId and v2.VoteTypeId = 2) as UserUpVotes,
    (select count(*) from Votes v2 where v2.UserId = ua.UserId and v2.VoteTypeId = 3) as UserDownVotes
  from RecursiveUserActivity ua
  left join UserBadgeSummary ub on ub.UserId = ua.UserId
),
WindowedPostStats AS (
  select 
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
    lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore,
    rank() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRank
  from Posts p 
  where p.PostTypeId = 1 -- questions only
),
QuestionsWithDuplicateLinks AS (
  select 
    tp.Id,
    tp.Title,
    tp.Score,
    coalesce(dl.DuplicateLinks, 0) as DuplicateCount,
    case 
      when tp.Tags is not null then array_length(string_to_array(replace(replace(tp.Tags, '<', ''), '>', '|'), '|'), 1)
      else 0
    end as TagCount
  from TopPosts tp
  left join DuplicateLinkCounts dl on dl.PostId = tp.Id
  where tp.PostTypeId = 1
)
select 
  ucm.UserId,
  ucm.DisplayName,
  ucm.Reputation,
  ucm.EditCount,
  ucm.PostCount,
  ucm.CommentCount,
  ucm.BadgeCount,
  ucm.GoldBadges,
  ucm.SilverBadges,
  ucm.BronzeBadges,
  ucm.EditsPerPost,
  ucm.UserUpVotes,
  ucm.UserDownVotes,
  wps.ScoreRank,
  qwd.DuplicateCount,
  qwd.TagCount,
  case 
    when qwd.TagCount > 3 then left(replace(qwd.Title, '&', 'and'), 100)
    else qwd.Title
  end as ProcessedQuestionTitle,
  /* Complex predicate with multiple AND, OR, and NULL logic */
  case 
    when ucm.EditCount > 10 and ucm.BadgeCount is not null and (ucm.GoldBadges > 0 or ucm.SilverBadges > 5)
      and (qwd.DuplicateCount < 2 or qwd.TagCount > 5) 
      and (uReputationAgg.MaxScore is null or uReputationAgg.MaxScore > 100)
      then 'PowerUser'
    when ucm.PostCount = 0 and ucm.CommentCount > 50 then 'Commenter'
    else 'RegularUser'
  end as UserCategory
from UserComplexMetrics ucm
left join WindowedPostStats wps on wps.OwnerUserId = ucm.UserId and wps.ScoreRank = 1
left join QuestionsWithDuplicateLinks qwd on qwd.Id = wps.Id
left join (
  select OwnerUserId, max(Score) as MaxScore
  from Posts 
  where PostTypeId = 1
  group by OwnerUserId
) uReputationAgg on uReputationAgg.OwnerUserId = ucm.UserId
where ucm.Reputation > 1000
order by ucm.Reputation desc, ucm.BadgeCount desc
limit 100;