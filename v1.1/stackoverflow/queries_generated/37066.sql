-- {"query": "37066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2014} 
WITH
-- recent active questions with tags exploded
Questions AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.AnswerCount,
    p.CommentCount,
    trim(both '<>' from unnest(string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><'))) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '2 years'
),
-- best answer info per question
TopAnswers AS (
  SELECT a.ParentId AS QuestionId,
         a.Id AS AnswerId,
         a.OwnerUserId AS AnswerOwner,
         a.Score AS AnswerScore,
         a.CreationDate AS AnswerCreationDate,
         ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate) AS rn
  FROM Posts a
  WHERE a.PostTypeId = 2
),
TopAnswerPerQuestion AS (
  SELECT QuestionId, AnswerId, AnswerOwner, AnswerScore, AnswerCreationDate
  FROM TopAnswers
  WHERE rn = 1
),
-- aggregated vote patterns for questions and answers in the period
RecentVotes AS (
  SELECT v.PostId,
         SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
         COUNT(*) AS TotalVotes
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE v.CreationDate >= now() - interval '1 year'
  GROUP BY v.PostId
),
-- recent activity count from PostHistory types per post
RecentEdits AS (
  SELECT ph.PostId,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,24)) AS EditCount,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (10,11)) AS CloseReopenEvents,
         MAX(ph.CreationDate) AS LastEditDate
  FROM PostHistory ph
  WHERE ph.CreationDate >= now() - interval '1 year'
  GROUP BY ph.PostId
),
-- user signals
UserSignals AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         u.CreationDate AS UserCreation,
         u.Views AS ProfileViews,
         u.UpVotes AS GivenUpVotes,
         u.DownVotes AS GivenDownVotes,
         COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
         COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
         COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
         CASE WHEN u.Reputation >= 10000 THEN 1 ELSE 0 END AS HighRep
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id
),
-- compute related link metrics (duplicates & links)
LinkMetrics AS (
  SELECT pl.PostId,
         COUNT(*) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateLinksOut,
         COUNT(*) FILTER (WHERE lt.Name = 'Linked') AS LinkedOut,
         COUNT(*) FILTER (WHERE lt.Name = 'Duplicate' AND pl.RelatedPostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)) AS DuplicateLinksToQuestion
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE pl.CreationDate >= now() - interval '2 years'
  GROUP BY pl.PostId
),
-- tag-level trending score combining views, answers, votes, and edits
TagTrend AS (
  SELECT
    q.Tag,
    COUNT(DISTINCT q.Id) AS QuestionCount,
    SUM(q.ViewCount) AS TotalViews,
    SUM(q.Score) AS TotalScore,
    SUM(COALESCE(rv.UpVotes,0) - COALESCE(rv.DownVotes,0)) AS NetRecentVotes,
    SUM(COALESCE(te.EditCount,0)) AS RecentEdits,
    SUM(COALESCE(tm.DuplicateLinksOut,0)) AS DuplicateOut
  FROM Questions q
  LEFT JOIN RecentVotes rv ON rv.PostId = q.Id
  LEFT JOIN RecentEdits te ON te.PostId = q.Id
  LEFT JOIN LinkMetrics tm ON tm.PostId = q.Id
  GROUP BY q.Tag
),
-- rank tags by a composite trending score
TagRank AS (
  SELECT
    Tag,
    QuestionCount,
    TotalViews,
    TotalScore,
    NetRecentVotes,
    RecentEdits,
    DuplicateOut,
    ( -- composite score: weight views moderately, votes high, edits small, penalize duplicates
      (LOG(GREATEST(TotalViews,1)) * 1.2)
      + (NetRecentVotes * 3.0)
      + (RecentEdits * 1.5)
      + (QuestionCount * 0.5)
      - (DuplicateOut * 2.0)
    ) AS TrendScore
  FROM TagTrend
),
-- pick top tags to drill into
TopTags AS (
  SELECT Tag
  FROM TagRank
  ORDER BY TrendScore DESC
  LIMIT 25
),
-- assemble final enriched question rows for the top tags
EnrichedQuestions AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.Tag,
    q.CreationDate,
    q.Score AS QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.CommentCount,
    COALESCE(rv.UpVotes,0) AS RecentUpVotes,
    COALESCE(rv.DownVotes,0) AS RecentDownVotes,
    COALESCE(te.EditCount,0) AS RecentEditCount,
    COALESCE(lm.DuplicateLinksOut,0) AS DuplicateLinksOut,
    ta.AnswerId AS TopAnswerId,
    ta.AnswerOwner,
    ta.AnswerScore,
    us.Reputation AS OwnerReputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    ROW_NUMBER() OVER (PARTITION BY q.Tag ORDER BY (q.Score * 1.5 + COALESCE(rv.UpVotes,0)*3 + GREATEST(q.ViewCount,0)/100.0) DESC) AS TagRankWithin
  FROM Questions q
  LEFT JOIN RecentVotes rv ON rv.PostId = q.Id
  LEFT JOIN RecentEdits te ON te.PostId = q.Id
  LEFT JOIN LinkMetrics lm ON lm.PostId = q.Id
  LEFT JOIN TopAnswerPerQuestion ta ON ta.QuestionId = q.Id
  LEFT JOIN UserSignals us ON us.UserId = q.OwnerUserId
  WHERE q.Tag IN (SELECT Tag FROM TopTags)
),
-- windowed aggregates per tag for percentiles and diversity
TagAggregates AS (
  SELECT
    Tag,
    COUNT(*) AS QuestionsInTop,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY QuestionScore) AS MedianScore,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY QuestionScore) AS P90Score,
    MAX(QuestionScore) AS MaxScore,
    AVG(ViewCount) AS AvgViews,
    SUM(CASE WHEN OwnerReputation >= 10000 THEN 1 ELSE 0 END) AS HighRepOwners
  FROM EnrichedQuestions
  GROUP BY Tag
)
SELECT
  et.Tag,
  ta.TrendScore,
  ta.QuestionCount,
  ta.TotalViews,
  ta.NetRecentVotes,
  ta.RecentEdits,
  ag.QuestionsInTop,
  ag.MedianScore,
  ag.P90Score,
  ag.MaxScore,
  ag.AvgViews,
  ag.HighRepOwners,
  json_agg(
    json_build_object(
      'QuestionId', eq.QuestionId,
      'Title', left(eq.Title,200),
      'Score', eq.QuestionScore,
      'Views', eq.ViewCount,
      'Answers', eq.AnswerCount,
      'RecentUpVotes', eq.RecentUpVotes,
      'RecentDownVotes', eq.RecentDownVotes,
      'RecentEdits', eq.RecentEditCount,
      'DuplicateLinksOut', eq.DuplicateLinksOut,
      'TopAnswerId', eq.TopAnswerId,
      'TopAnswerScore', eq.AnswerScore,
      'OwnerReputation', eq.OwnerReputation,
      'OwnerBadges', json_build_object('gold', eq.GoldBadges, 'silver', eq.SilverBadges, 'bronze', eq.BronzeBadges)
    ) ORDER BY eq.TagRankWithin
  ) FILTER (WHERE eq.QuestionId IS NOT NULL) AS TopQuestions
FROM TagRank ta
JOIN TopTags tt ON tt.Tag = ta.Tag
LEFT JOIN TagAggregates ag ON ag.Tag = ta.Tag
LEFT JOIN EnrichedQuestions eq ON eq.Tag = ta.Tag AND eq.TagRankWithin <= 10
LEFT JOIN TagTrend et ON et.Tag = ta.Tag
GROUP BY et.Tag, ta.TrendScore, ta.QuestionCount, ta.TotalViews, ta.NetRecentVotes, ta.RecentEdits, ag.QuestionsInTop, ag.MedianScore, ag.P90Score, ag.MaxScore, ag.AvgViews, ag.HighRepOwners
ORDER BY ta.TrendScore DESC, ag.QuestionsInTop DESC
LIMIT 25;