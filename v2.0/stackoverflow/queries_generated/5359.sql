-- {"query": "5359.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 806} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.AccountId,
    -- Window functions for benchmarking
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_type_desc,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVotesForPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DownVotesForPost,
    COUNT(*) OVER (PARTITION BY p.Id) AS LinkCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Tags t ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
  WHERE p.PostTypeId IN (1,2) -- focus on Questions and Answers
),
CorrelatedStats AS (
  SELECT
    rp.*,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCountForPost,
    (SELECT MAX(CASE WHEN pv.VoteTypeId = 2 THEN pv.CreationDate END)
       FROM Votes pv WHERE pv.PostId = rp.PostId) AS LastUpvoteDate,
    (SELECT STRING_AGG(CONCAT('=', pv.VoteTypeId, ':', pv.UserId), ',')
       FROM Votes pv WHERE pv.PostId = rp.PostId) AS VoteSummary
  FROM RankedPosts rp
),
OuterJoinsBenchmark AS (
  SELECT
    cs.PostId,
    cs.Title,
    cs.OwnerDisplayName,
    cs.Reputation,
    cs.CommentCountForPost,
    cs.UpVotesForPost,
    cs.DownVotesForPost,
    cs.ViewCount,
    cs.Score,
    cs.LastActivityDate,
    cs.CreationDate,
    cs.LinkCount,
    cs.rn_type_desc,
    cs.LastUpvoteDate,
    cs.VoteSummary,
    -- Complex expression with NULL handling and string operations
    COALESCE(NULLIF(cs.Title, ''), 'Untitled') AS TitleOrDefault,
    CONCAT('[', cs.OwnerDisplayName, '] (Rep:', cs.Reputation, ')') AS OwnerBrief,
    CASE
      WHEN cs.Score >= 10 THEN 'HighScore'
      WHEN cs.Score >= 0 THEN 'Positive'
      ELSE 'Negative'
    END AS ScoreCategory,
    CASE
      WHEN cs.LinkCount IS NULL THEN 0
      ELSE cs.LinkCount * 1
    END AS LinkFactor
  FROM CorrelatedStats cs
  LEFT JOIN Votes v2 ON v2.PostId = cs.PostId
  LEFT JOIN PostLinks pl2 ON pl2.PostId = cs.PostId
  LEFT JOIN Users u2 ON cs.OwnerUserId = u2.Id
  WHERE cs.rn_type_desc <= 50
)
SELECT
  *
FROM OuterJoinsBenchmark
WHERE
  LastActivityDate > DATEADD(day, -30, GETDATE())
  AND (CommentCountForPost IS NULL OR CommentCountForPost < 100)
ORDER BY LastActivityDate DESC
LIMIT 100;