-- {"query": "1092.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1784} 
with RecursiveUserActivity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    p.Id as PostId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate as PostCreationDate,
    row_number() over (partition by u.Id order by p.CreationDate) as PostSequence
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
),
FilteredPosts as (
  select
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    p.AnswerCount,
    p.FavoriteCount,
    p.ClosedDate,
    case when p.ClosedDate is null then 0 else 1 end as IsClosed,
    (length(coalesce(p.Tags, '')) - length(replace(coalesce(p.Tags, ''), '><', '')) + 1)/2 as TagCount
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate > current_date - interval '365 day'
),
PostScoresCTE as (
  select
    f.Id,
    f.Title,
    f.Tags,
    f.Score,
    f.ViewCount,
    f.CreationDate,
    f.OwnerUserId,
    f.AcceptedAnswerId,
    f.AnswerCount,
    f.FavoriteCount,
    f.IsClosed,
    f.TagCount,
    sum(v.VoteTypeId = 2)::int as UpVotes,
    sum(v.VoteTypeId = 3)::int as DownVotes,
    coalesce(
      (select count(*) from Comments c where c.PostId = f.Id), 0) as CommentCount
  from FilteredPosts f
  left join Votes v on v.PostId = f.Id
  group by f.Id, f.Title, f.Tags, f.Score, f.ViewCount, f.CreationDate, f.OwnerUserId, f.AcceptedAnswerId, f.AnswerCount, f.FavoriteCount, f.IsClosed, f.TagCount
),
PostRanking as (
  select
    p.*,
    rank() over (
      partition by p.IsClosed
      order by (p.Score * 1.5 + p.ViewCount * 0.3 + coalesce(p.FavoriteCount,0) * 2 + p.UpVotes * 0.7 - p.DownVotes * 1.0)::numeric desc, p.CreationDate desc) as RankScore
  from PostScoresCTE p
),
UserBadgeSummary as (
  select
    b.UserId,
    count(*) filter (where b.Class = 1) as GoldBadges,
    count(*) filter (where b.Class = 2) as SilverBadges,
    count(*) filter (where b.Class = 3) as BronzeBadges,
    count(*) as TotalBadges,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
TopUsers as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    coalesce(bs.TotalBadges, 0) as TotalBadges,
    coalesce(bs.GoldBadges, 0) as GoldBadges,
    coalesce(bs.SilverBadges, 0) as SilverBadges,
    coalesce(bs.BronzeBadges, 0) as BronzeBadges,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    row_number() over (order by u.Reputation desc, coalesce(bs.TotalBadges, 0) desc, u.Views desc) as UserRank
  from Users u
  left join UserBadgeSummary bs on bs.UserId = u.Id
  where u.Reputation > 1000
),
UserTopQuestionStats as (
  select
    t.UserId,
    count(p.Id) as TotalQuestions,
    sum(p.Score) as TotalQuestionScore,
    avg(p.Score) as AvgQuestionScore,
    sum(p.ViewCount) as TotalQuestionViews,
    sum(p.FavoriteCount) as TotalQuestionFavorites,
    sum(case when p.IsClosed = 1 then 1 else 0 end) as ClosedQuestions,
    max(p.Score) as MaxQuestionScore
  from TopUsers t
  left join Posts p on p.OwnerUserId = t.UserId and p.PostTypeId = 1
  group by t.UserId
),
QuestionWithComments as (
  select
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CreationDate,
    count(c.Id) as CommentCount,
    max(coalesce(c.CreationDate, '1900-01-01'::timestamp)) as LastCommentDate
  from Posts p
  left join Comments c on c.PostId = p.Id
  where p.PostTypeId = 1
  group by p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.Tags, p.CreationDate
),
LatestPostHistoryEdit as (
  select distinct on (ph.PostId)
    ph.PostId,
    ph.Id as PostHistoryId,
    ph.PostHistoryTypeId,
    ph.CreationDate as EditDate,
    ph.UserId as EditorUserId,
    ph.UserDisplayName as EditorDisplayName,
    ph.Comment
  from PostHistory ph
  where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
  order by ph.PostId, ph.CreationDate desc
),
DuplicateQuestionLinks as (
  select
    pl.PostId,
    pl.RelatedPostId
  from PostLinks pl
  where pl.LinkTypeId = 3
),
QuestionsDupCount as (
  select
    d.PostId,
    count(d.RelatedPostId) as DuplicateCount
  from DuplicateQuestionLinks d
  group by d.PostId
),
QuestionsWithDuplicates as (
  select
    p.Id,
    coalesce(qd.DuplicateCount,0) as DuplicateCount
  from Posts p
  left join QuestionsDupCount qd on qd.PostId = p.Id
  where p.PostTypeId = 1
)
select
  u.UserRank,
  u.DisplayName,
  u.Reputation,
  u.TotalBadges,
  u.GoldBadges,
  u.SilverBadges,
  u.BronzeBadges,
  ua.TotalQuestions,
  ua.TotalQuestionScore,
  ua.AvgQuestionScore,
  ua.TotalQuestionViews,
  ua.TotalQuestionFavorites,
  ua.ClosedQuestions,
  ua.MaxQuestionScore,
  p.Id as QuestionId,
  p.Title,
  substring(p.Tags from '>[^><]+' for 20) as FirstTag,
  p.Score as QuestionScore,
  p.ViewCount as QuestionViews,
  p.CommentCount,
  p.LastCommentDate,
  ph.EditDate as LastEditDate,
  ph.EditorDisplayName as LastEditor,
  qd.DuplicateCount,
  case
    when p.Score > avg(p.Score) over () then 'AboveAverage'
    else 'BelowAverage'
  end as ScoreComparedToAvg,
  (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 14) as SuggestEdits,
  array_agg(distinct b.Name order by b.Class, b.Date) filter (where b.UserId = u.UserId) as BadgesList,
  case
    when ph.EditDate is null then 'NeverEdited'
    else 'Edited'
  end as EditStatus
from
  TopUsers u
  left join UserTopQuestionStats ua on ua.UserId = u.UserId
  left join QuestionWithComments p on p.OwnerUserId = u.UserId
  left join LatestPostHistoryEdit ph on ph.PostId = p.Id
  left join QuestionsWithDuplicates qd on qd.Id = p.Id
  left join Badges b on b.UserId = u.UserId
where
  p.Score is not null
  and p.CreationDate > current_date - interval '180 day'
order by
  u.UserRank,
  p.Score desc
limit 100;