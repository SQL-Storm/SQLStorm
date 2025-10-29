with RecursivePostVotes as (
  select
    p.Id as PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    coalesce(vt.Name, 'NoVotes') as VoteTypeName,
    count(v.Id) as VoteCount
  from Posts p
  left join Votes v on v.PostId = p.Id
  left join VoteTypes vt on v.VoteTypeId = vt.Id
  group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, vt.Name
), UserBadgeCounts as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    count(case when b.Class = 1 then 1 end) as GoldBadges,
    count(case when b.Class = 2 then 1 end) as SilverBadges,
    count(case when b.Class = 3 then 1 end) as BronzeBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation
), TopPostsByTag as (
  select
    p.Id,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    t.TagName,
    row_number() over (partition by t.TagName order by p.Score desc, p.ViewCount desc) as rn
  from Posts p
  cross join lateral (
    select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName
  ) t
  where p.PostTypeId = 1 and p.Tags is not null
), PostsWithLockedStatus as (
  select
    p.Id,
    p.Title,
    p.OwnerUserId,
    case when exists (
      select 1 from PostHistory ph 
      where ph.PostId = p.Id and ph.PostHistoryTypeId = 14
      and ph.CreationDate > p.CreationDate
    ) then 'Locked' else 'Unlocked' end as LockStatus
  from Posts p
  where p.PostTypeId in (1, 2)
), RecursiveCommentStats as (
  select
    c.PostId,
    count(c.Id) as CommentCount,
    sum(coalesce(c.Score, 0)) as CommentScoreSum,
    max(c.CreationDate) as LastCommentDate
  from Comments c
  group by c.PostId
), ComplexUserMetrics as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
    count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
    max(p.Score) as MaxPostScore,
    min(p.Score) as MinPostScore,
    avg(p.Score) as AvgPostScore,
    count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as TimesPostsClosed,
    count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 11) as TimesPostsReopened,
    sum(b.Class) as BadgeClassSum,
    bool_or(p.ClosedDate is not null) as HasClosedPosts
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join PostHistory ph on ph.PostId = p.Id and ph.UserId = u.Id
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation
), SetOperatorExample as (
  select p.Id, p.Title, 'HighScore' as Category from Posts p where p.Score >= 100
  union
  select p.Id, p.Title, 'Popular' as Category from Posts p where p.ViewCount >= 10000
), WindowedVotes as (
  select
    v.PostId,
    v.VoteTypeId,
    vt.Name as VoteTypeName,
    count(*) over (partition by v.VoteTypeId order by v.CreationDate rows between unbounded preceding and current row) as RunningVoteCount,
    row_number() over (partition by v.PostId order by v.CreationDate desc) as VoteRankForPost
  from Votes v
  join VoteTypes vt on v.VoteTypeId = vt.Id
), FinalSelection as (
  select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    cu.QuestionsAsked,
    cu.AnswersGiven,
    cu.MaxPostScore,
    cu.MinPostScore,
    cu.AvgPostScore,
    cu.TimesPostsClosed,
    cu.TimesPostsReopened,
    sw.Category,
    tpbt.TagName,
    tpbt.Title as TopTagTitle,
    pwls.LockStatus,
    rcs.CommentCount,
    rcs.CommentScoreSum,
    rcs.LastCommentDate
  from Users u
  left join UserBadgeCounts ub on ub.UserId = u.Id
  left join ComplexUserMetrics cu on cu.Id = u.Id
  left join SetOperatorExample sw on sw.Id = (
    select p.Id 
    from Posts p 
    where p.OwnerUserId = u.Id
    order by p.Score desc nulls last limit 1
  )
  left join TopPostsByTag tpbt on tpbt.rn = 1
  left join PostsWithLockedStatus pwls on pwls.OwnerUserId = u.Id
  left join RecursiveCommentStats rcs on rcs.PostId = (
    select p.Id from Posts p where p.OwnerUserId = u.Id order by p.CreationDate desc limit 1
  )
  where u.Reputation > 1000
)
select 
  fs.UserId,
  fs.DisplayName,
  fs.Reputation,
  fs.GoldBadges,
  fs.SilverBadges,
  fs.BronzeBadges,
  fs.QuestionsAsked,
  fs.AnswersGiven,
  fs.MaxPostScore,
  fs.MinPostScore,
  round(fs.AvgPostScore,2) as AvgPostScore,
  fs.TimesPostsClosed,
  fs.TimesPostsReopened,
  fs.Category,
  fs.TagName as FavoriteTag,
  fs.TopTagTitle,
  fs.LockStatus,
  fs.CommentCount,
  fs.CommentScoreSum,
  fs.LastCommentDate,
  case 
    when fs.Reputation > 5000 and fs.GoldBadges >= 10 then 'Elite User'
    when fs.Reputation > 2000 and fs.SilverBadges >= 20 then 'Experienced User'
    else 'Normal User'
  end as UserLevel,
  (select count(*) from Posts p where p.OwnerUserId = fs.UserId and lower(p.Title) like '%sql%') as SqlMentionsInTitles,
  (select count(*) from Comments c where c.UserId = fs.UserId and lower(c.Text) like '%performance%') as PerformanceMentionsInComments
from FinalSelection fs
order by fs.Reputation desc, fs.GoldBadges desc, fs.QuestionsAsked desc
limit 100;