-- {"query": "5210.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1190} 
WITH
TagsExpanded AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.Tags,
    p.PostTypeId,
    uuid() AS RunId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagNames AS (
  SELECT
    te.PostId,
    unnest(string_to_array(substring(te.Tags, 2, length(te.Tags)-2), '><')) AS TagName,
    te.CreationDate,
    te.Score,
    te.ViewCount,
    te.OwnerUserId,
    te.LastActivityDate,
    te.AnswerCount,
    te.CommentCount
  FROM TagsExpanded te
),
TopTags AS (
  SELECT
    tn.TagName,
    COUNT(*) AS PostCount,
    AVG(te.Score) AS AvgScore,
    MAX(te.ViewCount) AS MaxViews,
    MIN(te.CreationDate) AS FirstPostDate
  FROM TagNames tn
  JOIN TagsExpanded te ON te.PostId = tn.PostId
  GROUP BY tn.TagName
  ORDER BY PostCount DESC
  LIMIT 10
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE(b.TotalBadges, 0) AS TotalBadges,
    COUNT(DISTINCT te.PostId) FILTER (WHERE te.PostTypeId = 1) AS UserQuestions,
    COUNT(DISTINCT a.PostId) FILTER (WHERE a.PostTypeId = 2) AS UserAnswers
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Posts te ON te.OwnerUserId = u.Id
  LEFT JOIN Posts a ON a.OwnerUserId = u.Id
  GROUP BY u.Id
),
CorrelatedScores AS (
  SELECT
    wt.PostId,
    wt.VoteTypeId,
    wt.BountyAmount,
    wt.UserId AS VoterId,
    wt.CreationDate AS VoteDate,
    CASE
      WHEN wt.VoteTypeId = 2 THEN 1
      WHEN wt.VoteTypeId = 3 THEN -1
      ELSE 0
    END AS ScoreDelta
  FROM Votes wt
  WHERE wt.VoteTypeId IN (2,3)
),
PostLinkSummary AS (
  SELECT
    pl.PostId,
    COUNT(*) AS LinkCount,
    MAX(pl.CreationDate) AS LastLinkDate
  FROM PostLinks pl
  GROUP BY pl.PostId
),
PostTagRelation AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.Tags,
    pt.TagName
  FROM Posts p
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) pt ON TRUE
)
SELECT
  -- Outer join and complex predicates with window functions and NULL handling
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.AccountId,
  u.Location,
  u.AboutMe,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  COALESCE(bd.TotalBadges, 0) AS BadgesCount,
  wtV.SumScoreOverTime,
  qt.PostWithTag AS MostLovedQuestionTag,
  tgs.TopTagName,
  a.LastAnswerDate,
  agg.SinceCreation
FROM Users u
LEFT JOIN (
  SELECT
    UserId,
    SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS SumScoreOverTime
  FROM Votes
  GROUP BY UserId
) wtV ON wtV.UserId = u.Id
LEFT JOIN (
  SELECT
    t.TagName AS MostLovedQuestionTag,
    MAX(p.LastActivityDate) AS LastAnswerDate
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) t ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
  ORDER BY MAX(p.Score) DESC
  LIMIT 1
) qt ON TRUE
LEFT JOIN (
  SELECT
    t.TagName AS TopTagName,
    COUNT(*) AS TagPostCount
  FROM TagNames t
  GROUP BY t.TagName
  ORDER BY TagPostCount DESC
  LIMIT 1
) tgs ON TRUE
LEFT JOIN (
  SELECT
    p.OwnerUserId AS UserId,
    MAX(p.LastActivityDate) AS SinceCreation
  FROM Posts p
  GROUP BY p.OwnerUserId
) agg ON agg.UserId = u.Id
LEFT JOIN (
  SELECT
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS TotalGoldBadges,
    UserId
  FROM Badges
  WHERE TagBased = 0
  GROUP BY UserId
) bd ON bd.UserId = u.Id
WHERE
  u.Reputation > 1000
  AND (u.Location IS NULL OR u.Location <> '')
ORDER BY u.Reputation DESC, u.Id
LIMIT 100;