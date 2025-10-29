-- {"query": "2282.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1338} 
with RecursivePosts as (
    select p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.AcceptedAnswerId, p.Title, p.Tags, p.CreationDate,
      0 as Level
    from Posts p
    where p.PostTypeId = 1 and p.CreationDate > now() - interval '1 year'
    
    union all
    
    select c.Id, c.PostTypeId, c.OwnerUserId, c.Score, c.ViewCount, c.AcceptedAnswerId, c.Title, c.Tags, c.CreationDate,
      rp.Level + 1
    from Posts c
    join RecursivePosts rp on c.ParentId = rp.Id
    where c.PostTypeId = 2
),
UserBadgeCounts as (
    select b.UserId,
      count(*) filter (where b.Class = 1) as GoldBadges,
      count(*) filter (where b.Class = 2) as SilverBadges,
      count(*) filter (where b.Class = 3) as BronzeBadges
    from Badges b
    group by b.UserId
),
LatestPostHistory as (
    select ph.PostId, ph.PostHistoryTypeId, ph.CreationDate,
      row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
),
PostCloseInfo as (
    select lph.PostId, cr.Name as CloseReason, count(*) as CloseVotes
    from LatestPostHistory lph
    left join CloseReasonTypes cr on cr.Id = try_cast(lph.Comment as int)
    where lph.PostHistoryTypeId = 10
    group by lph.PostId, cr.Name
),
UserActivityWindow as (
    select 
      u.Id as UserId,
      u.DisplayName,
      u.Reputation,
      count(distinct p.Id) as TotalPosts,
      count(distinct case when p.PostTypeId = 1 then p.Id end) as Questions,
      count(distinct case when p.PostTypeId = 2 then p.Id end) as Answers,
      coalesce(sum(p.Score),0) as TotalPostScore,
      max(p.Score) as HighestPostScore,
      min(p.Score) as LowestPostScore,
      avg(p.Score) as AvgPostScore,
      count(distinct c.Id) as CommentsMade,
      coalesce(sum(v.VoteTypeId = 2::bit)::int, 0) as UpVotesGiven,
      count(distinct b.Id) as BadgeCount,
      max(pb.GoldBadges) as GoldBadges,
      max(pb.SilverBadges) as SilverBadges,
      max(pb.BronzeBadges) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate > now() - interval '1 year'
    left join Comments c on c.UserId = u.Id and c.CreationDate > now() - interval '1 year'
    left join Votes v on v.UserId = u.Id and v.CreationDate > now() - interval '1 year'
    left join Badges b on b.UserId = u.Id and b.Date > now() - interval '1 year'
    left join UserBadgeCounts pb on pb.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
QuestionAnswerStats as (
    select 
      q.Id as QuestionId, q.Title, q.CreationDate as QuestionDate, q.Tags, q.Score as QuestionScore, q.ViewCount,
      a.Id as AnswerId, a.OwnerUserId as AnswerOwnerUserId, a.Score as AnswerScore, a.CreationDate as AnswerDate,
      rank() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.CreationDate > now() - interval '2 years'
),
HighActivityUsers as (
    select UserId
    from UserActivityWindow
    where TotalPosts > 100 and Reputation > 5000
),
DuplicatedLinks as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate, lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where pl.LinkTypeId = 3
)
select 
  uaw.UserId,
  uaw.DisplayName,
  uaw.Reputation,
  uaw.TotalPosts,
  uaw.Questions,
  uaw.Answers,
  uaw.TotalPostScore,
  uaw.HighestPostScore,
  uaw.LowestPostScore,
  uaw.AvgPostScore,
  uaw.CommentsMade,
  uaw.UpVotesGiven,
  uaw.GoldBadges,
  uaw.SilverBadges,
  uaw.BronzeBadges,
  qa.QuestionId,
  qa.Title,
  qa.QuestionScore,
  qa.ViewCount,
  qa.AnswerId,
  qa.AnswerOwnerUserId,
  qa.AnswerScore,
  qa.AnswerRank,
  pc.CloseReason,
  pc.CloseVotes,
  dl.RelatedPostId as DuplicateOfPost,
  concat_ws(' | ',
    coalesce(uaw.DisplayName, 'NoUser'),
    'Posts: ' || uaw.TotalPosts,
    'ScoreAvg: ' || coalesce(round(uaw.AvgPostScore::numeric,2),0),
    'Gold Badges: ' || coalesce(uaw.GoldBadges::text, '0')
  ) as UserSummary
from HighActivityUsers hau
join UserActivityWindow uaw on hau.UserId = uaw.UserId
left join QuestionAnswerStats qa on qa.AnswerOwnerUserId = uaw.UserId and qa.AnswerRank = 1
left join PostCloseInfo pc on pc.PostId = qa.QuestionId
left join DuplicatedLinks dl on dl.PostId = qa.QuestionId
where qa.QuestionScore > 10 or uaw.GoldBadges > 0
order by uaw.Reputation desc, qa.QuestionScore desc NULLS LAST, qa.AnswerScore desc NULLS LAST
limit 100;