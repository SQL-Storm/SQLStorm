-- {"query": "37069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2040} 
WITH
-- recent active questions with tag exploded
QuestionBase AS (
  SELECT p.Id AS QuestionId,
         p.Title,
         p.OwnerUserId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.FavoriteCount,
         p.Tags,
         regexp_split_to_table(substring(p.Tags,2,length(p.Tags)-2),'><') AS TagName
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '5 years'
),
-- top answer per question (highest score, tie break by latest)
TopAnswers AS (
  SELECT a.ParentId AS QuestionId,
         a.Id AS AnswerId,
         a.OwnerUserId AS AnswerOwner,
         a.Score AS AnswerScore,
         a.CreationDate AS AnswerCreation,
         row_number() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate DESC, a.Id) rn
  FROM Posts a
  WHERE a.PostTypeId = 2
),
TopAnswerFiltered AS (
  SELECT * FROM TopAnswers WHERE rn = 1
),
-- aggregate comments on question and its top answer
CommentAgg AS (
  SELECT c.PostId,
         count(*) FILTER (WHERE c.CreationDate >= now() - interval '1 year') AS RecentComments,
         count(*) AS TotalComments,
         max(c.CreationDate) AS LastCommentDate
  FROM Comments c
  WHERE c.CreationDate IS NOT NULL
  GROUP BY c.PostId
),
-- badge summary for question owners and answer owners
BadgeAgg AS (
  SELECT b.UserId,
         count(*) FILTER (WHERE b.Class = 1) AS Gold,
         count(*) FILTER (WHERE b.Class = 2) AS Silver,
         count(*) FILTER (WHERE b.Class = 3) AS Bronze,
         bool_or(b.TagBased) AS HasTagBadges,
         count(*) AS TotalBadges
  FROM Badges b
  GROUP BY b.UserId
),
-- recent close/reopen/edit history counts per question
HistoryAgg AS (
  SELECT ph.PostId,
         count(*) FILTER (WHERE ph.PostHistoryTypeId IN (10,11,12,13)) AS CloseReopenDeletes,
         count(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,24)) AS Edits,
         min(ph.CreationDate) AS FirstHistory,
         max(ph.CreationDate) AS LastHistory
  FROM PostHistory ph
  GROUP BY ph.PostId
),
-- link graph metrics (inbound links, outbound links, duplicates)
LinkAgg AS (
  SELECT pl.PostId,
         count(*) FILTER (WHERE pl.LinkTypeId = 1) AS OutboundLinks,
         count(*) FILTER (pl.LinkTypeId = 3) AS MarkedDuplicates,
         (SELECT count(*) FROM PostLinks pl2 WHERE pl2.RelatedPostId = pl.PostId) AS InboundLinks
  FROM PostLinks pl
  GROUP BY pl.PostId
),
-- vote summary on questions and answers
VoteAgg AS (
  SELECT v.PostId,
         count(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
         count(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
         count(*) FILTER (WHERE v.VoteTypeId = 5) AS Favorites,
         count(*) AS TotalVotes,
         sum(CASE WHEN v.VoteTypeId = 8 OR v.VoteTypeId = 9 THEN coalesce(v.BountyAmount,0) ELSE 0 END) AS BountySum
  FROM Votes v
  GROUP BY v.PostId
),
-- user snapshots for owners and answerers
UserSnap AS (
  SELECT u.Id,
         u.Reputation,
         u.CreationDate AS UserCreation,
         u.DisplayName,
         u.Views AS UserViews,
         u.UpVotes AS UserUpVotes,
         u.DownVotes AS UserDownVotes
  FROM Users u
),
-- per-tag popularity and growth indicators
TagMetrics AS (
  SELECT q.TagName,
         count(distinct q.QuestionId) AS Questions,
         avg(q.Score) AS AvgQuestionScore,
         sum(q.ViewCount) AS TotalViews,
         count(distinct t.ExcerptPostId) FILTER (WHERE t.ExcerptPostId IS NOT NULL) AS HasExcerptCount
  FROM QuestionBase q
  LEFT JOIN Tags t ON t.TagName = q.TagName
  GROUP BY q.TagName
),
-- final assembled rows, joining lots of data to stress planner
FinalBase AS (
  SELECT q.QuestionId,
         q.Title,
         q.TagName,
         q.CreationDate AS QuestionCreation,
         q.Score AS QuestionScore,
         q.ViewCount,
         q.AnswerCount,
         q.FavoriteCount,
         ta.AnswerId,
         ta.AnswerOwner,
         ta.AnswerScore,
         ca.RecentComments AS QRecentComments,
         ca.TotalComments AS QTotalComments,
         ha.CloseReopenDeletes,
         ha.Edits AS QEdits,
         la.OutboundLinks,
         la.InboundLinks,
         la.MarkedDuplicates,
         va.UpVotes AS QUpVotes,
         va.DownVotes AS QDownVotes,
         va.Favorites AS QFavorites,
         vb.UpVotes AS AUpVotes,
         vb.DownVotes AS ADownVotes,
         bq.Gold AS QOwnerGold,
         bq.Silver AS QOwnerSilver,
         bq.Bronze AS QOwnerBronze,
         ba.Gold AS AOwnerGold,
         ba.Silver AS AOwnerSilver,
         ba.Bronze AS AOwnerBronze,
         um.DisplayName AS QuestionOwnerName,
         ua.DisplayName AS AnswerOwnerName,
         tm.Questions AS TagQuestionCount,
         tm.TotalViews AS TagTotalViews,
         tm.AvgQuestionScore AS TagAvgScore
  FROM QuestionBase q
  LEFT JOIN TopAnswerFiltered ta ON ta.QuestionId = q.QuestionId
  LEFT JOIN CommentAgg ca ON ca.PostId = q.QuestionId
  LEFT JOIN CommentAgg ca2 ON ca2.PostId = ta.AnswerId
  LEFT JOIN HistoryAgg ha ON ha.PostId = q.QuestionId
  LEFT JOIN LinkAgg la ON la.PostId = q.QuestionId
  LEFT JOIN VoteAgg va ON va.PostId = q.QuestionId
  LEFT JOIN VoteAgg vb ON vb.PostId = ta.AnswerId
  LEFT JOIN BadgeAgg bq ON bq.UserId = q.OwnerUserId
  LEFT JOIN BadgeAgg ba ON ba.UserId = ta.AnswerOwner
  LEFT JOIN UserSnap um ON um.Id = q.OwnerUserId
  LEFT JOIN UserSnap ua ON ua.Id = ta.AnswerOwner
  LEFT JOIN TagMetrics tm ON tm.TagName = q.TagName
)
SELECT
  fb.QuestionId,
  fb.Title,
  fb.TagName,
  fb.QuestionCreation,
  fb.QuestionScore,
  fb.ViewCount,
  fb.AnswerCount,
  fb.FavoriteCount,
  fb.AnswerId,
  fb.AnswerScore,
  fb.AnswerOwner,
  fb.AnswerOwnerName,
  fb.QRecentComments,
  fb.QTotalComments,
  coalesce(fb.CloseReopenDeletes,0) AS CloseReopenDeletes,
  coalesce(fb.QEdits,0) AS QuestionEdits,
  coalesce(fb.OutboundLinks,0) AS OutboundLinks,
  coalesce(fb.InboundLinks,0) AS InboundLinks,
  coalesce(fb.MarkedDuplicates,0) AS MarkedDuplicates,
  coalesce(fb.QUpVotes,0) AS QUpVotes,
  coalesce(fb.QDownVotes,0) AS QDownVotes,
  coalesce(fb.QFavorites,0) AS QFavorites,
  coalesce(fb.BQOwnerGold,0) FILTER (WHERE false) AS force_noop, -- tiny no-op to add complexity
  coalesce(fb.AOwnerGold,0) FILTER (WHERE true) AS AOwnerGold,
  fb.QuestionOwnerName,
  fb.TagQuestionCount,
  fb.TagTotalViews,
  fb.TagAvgScore,
  -- composite ranking score combining many signals
  (
    (fb.QuestionScore * 3)
    + coalesce(fb.ViewCount,0)::numeric / greatest(1, sqrt(greatest(fb.TagQuestionCount,1)))
    + coalesce(fb.AnswerScore,0) * 4
    + coalesce(fb.QUpVotes,0) * 2
    - coalesce(fb.QDownVotes,0) * 1.5
    + coalesce(fb.QFavorites,0) * 5
    + coalesce(fb.QRecentComments,0) * 1.2
    + coalesce(fb.OutboundLinks,0) * 0.7
    + coalesce(fb.InboundLinks,0) * 0.9
    + coalesce(fb.MarkedDuplicates,0) * -10
    + coalesce(fb.TagAvgScore,0) * 2
    + coalesce(fb.TagTotalViews,0)::numeric / 10000
  ) AS CompositeScore
FROM FinalBase fb
WHERE fb.TagName IS NOT NULL
  AND fb.QuestionCreation >= now() - interval '3 years'
  -- interesting filter: high activity OR underserved (low answers but many views)
  AND (
     fb.AnswerCount >= 5
     OR (fb.AnswerCount <= 1 AND fb.ViewCount >= 1000)
  )
ORDER BY CompositeScore DESC NULLS LAST
LIMIT 200;