-- {"query": "2713.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1575} 
with RecursiveQuestions as (
    select p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score,
      row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate asc) as UserTopQuestionRank
    from Posts p
    where p.PostTypeId = 1 and p.Score is not null
),
UserBadgeCounts as (
    select 
      u.Id as UserId,
      sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
      sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
      sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id
),
UserActivityStats as (
    select 
      u.Id as UserId,
      count(distinct ph.PostId) filter (where ph.PostHistoryTypeId in (10,12)) as CloseOrDeletedPosts,
      count(distinct ph.PostId) filter (where ph.PostHistoryTypeId = 11) as ReopenedPosts,
      count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
      count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
      max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxPostScore,
      min(p.CreationDate) as FirstPostDate,
      max(p.CreationDate) as LastPostDate
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
QuestionsWithAnswersCounts AS (
    select q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.AnswerCount,
      (select count(*) from Posts a where a.ParentId = q.Id and a.Score > 0) as PositiveAnswerCount,
      (select count(*) from Posts a where a.ParentId = q.Id and a.Score <= 0) as NonPositiveAnswerCount,
      (select avg(a.Score) from Posts a where a.ParentId = q.Id) as AvgAnswerScore
    from Posts q
    where q.PostTypeId = 1
),
LatestCommentsPerPost AS (
    select distinct on (c.PostId) c.PostId, c.Id as CommentId, c.UserId as CommentUserId, c.CreationDate as CommentDate,
      left(c.Text, 100) as ShortText
    from Comments c
    order by c.PostId, c.CreationDate desc
),
PostLinkDuplicates AS (
    select pl.PostId, pl.RelatedPostId,
      case when lt.Name = 'Duplicate' then 1 else 0 end as IsDuplicateLink
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
),
UserDetailsEnriched AS (
    select 
      u.Id,
      u.DisplayName,
      u.Reputation,
      coalesce(ubc.GoldBadges,0) as GoldBadges,
      coalesce(ubc.SilverBadges,0) as SilverBadges,
      coalesce(ubc.BronzeBadges,0) as BronzeBadges,
      coalesce(uas.CloseOrDeletedPosts,0) as CloseOrDeletedPosts,
      coalesce(uas.ReopenedPosts,0) as ReopenedPosts,
      coalesce(uas.UpVotesGiven,0) as UpVotesGiven,
      coalesce(uas.DownVotesGiven,0) as DownVotesGiven,
      coalesce(uas.MaxPostScore,0) as MaxPostScore,
      uas.FirstPostDate,
      uas.LastPostDate
    from Users u
    left join UserBadgeCounts ubc on u.Id = ubc.UserId
    left join UserActivityStats uas on u.Id = uas.UserId
)
select
  ude.Id as UserId,
  ude.DisplayName,
  ude.Reputation,
  ude.GoldBadges, ude.SilverBadges, ude.BronzeBadges,
  ude.CloseOrDeletedPosts,
  ude.ReopenedPosts,
  ude.UpVotesGiven,
  ude.DownVotesGiven,
  ude.MaxPostScore,
  ude.FirstPostDate,
  ude.LastPostDate,
  rq.Id as TopQuestionId,
  rq.Title as TopQuestionTitle,
  rq.CreationDate as TopQuestionDate,
  rq.Score as TopQuestionScore,
  qac.AnswerCount,
  qac.PositiveAnswerCount,
  qac.NonPositiveAnswerCount,
  round(coalesce(qac.AvgAnswerScore,0),2) as AvgAnswerScore,
  lc.CommentId as LatestCommentIdOnQuestion,
  lc.CommentDate as LatestCommentDate,
  lc.CommentUserId as LatestCommentUserId,
  coalesce(pld.IsDuplicateLink,0) as HasDuplicateLink,
  case 
    when ude.LastPostDate is not null and ude.FirstPostDate is not null then
      extract(epoch from (ude.LastPostDate - ude.FirstPostDate))/86400::float
    else null
  end as DaysBetweenFirstAndLastPost,
  case
    when ude.Reputation > 10000 then 'HighRep'
    when ude.Reputation > 1000 then 'MediumRep'
    else 'LowRep'
  end as ReputationGroup,
  count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (10,12)) as UserClosedOrDeletedHistories,
  bool_or(ph.PostHistoryTypeId = 10) filter (where ph.PostId = rq.Id) as TopQuestionEverClosed,
  string_agg(distinct pt.Name, ', ') as PostTypesUserHas,
  max(ph.CreationDate) filter (where ph.PostId = rq.Id) as LastEditDateTopQuestion
from UserDetailsEnriched ude
left join RecursiveQuestions rq on rq.OwnerUserId = ude.Id and rq.UserTopQuestionRank = 1
left join QuestionsWithAnswersCounts qac on qac.Id = rq.Id
left join LatestCommentsPerPost lc on lc.PostId = rq.Id
left join PostLinkDuplicates pld on pld.PostId = rq.Id and pld.IsDuplicateLink = 1
left join PostHistory ph on ph.UserId = ude.Id
left join Posts p on p.OwnerUserId = ude.Id
left join PostTypes pt on pt.Id = p.PostTypeId
group by
  ude.Id, ude.DisplayName, ude.Reputation, ude.GoldBadges, ude.SilverBadges, ude.BronzeBadges,
  ude.CloseOrDeletedPosts, ude.ReopenedPosts, ude.UpVotesGiven, ude.DownVotesGiven, ude.MaxPostScore,
  ude.FirstPostDate, ude.LastPostDate,
  rq.Id, rq.Title, rq.CreationDate, rq.Score,
  qac.AnswerCount, qac.PositiveAnswerCount, qac.NonPositiveAnswerCount, qac.AvgAnswerScore,
  lc.CommentId, lc.CommentDate, lc.CommentUserId,
  pld.IsDuplicateLink
order by ude.Reputation desc nulls last, ude.GoldBadges desc nulls last, ude.SilverBadges desc nulls last
limit 100;