-- {"query": "5249.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 680} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.PostTypeId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Body,
    p.LastEditDate,
    p.LastEditorUserId,
    p.LastEditorDisplayName,
    p.OwnerDisplayName,
    u.Reputation,
    u.Location,
    u.AccountId,
    -- derived metrics
    CASE WHEN v1.Id IS NOT NULL THEN v1.BountyAmount ELSE 0 END AS BountyAwarded,
    SUM(CASE WHEN t.VoteTypeId IN (2) THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpvotesForPost
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v1 ON v1.PostId = p.Id AND v1.VoteTypeId = 2
  LEFT JOIN Votes v2 ON v2.PostId = p.Id AND v2.VoteTypeId = 3
  LEFT JOIN (SELECT * FROM Votes) t ON t.PostId = p.Id
  WHERE p.PostTypeId = 1
),
WithLinks AS (
  SELECT
    r.*,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM RankedPosts r
  LEFT JOIN PostLinks pl ON pl.PostId = r.PostId
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
WithTagStats AS (
  SELECT
    w.*
  FROM WithLinks w
  LEFT JOIN Tags t ON t.WikiPostId = w.PostId OR t.ExcerptPostId = w.PostId
),
WindowAgg AS (
  SELECT
    wts.*,
    ROW_NUMBER() OVER (
      PARTITION BY wts.PostId
      ORDER BY wts.CreationDate DESC
    ) AS rn_recent_change
  FROM WithTagStats wts
),
FinalPick AS (
  SELECT
    wa.*,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = wa.OwnerUserId) AS PostsByOwner
  FROM WindowAgg wa
  WHERE wa.rn_recent_change = 1
)
SELECT
  fp.PostId,
  fp.Title,
  fp.Tags,
  fp.CreationDate,
  fp.PostTypeId,
  fp.OwnerUserId,
  fp.Reputation AS OwnerReputation,
  fp.Location AS OwnerLocation,
  fp.ViewCount,
  fp.Score,
  fp.AnswerCount,
  fp.CommentCount,
  fp.FavoriteCount,
  fp.LastActivityDate,
  fp.Body,
  fp.BountyAwarded,
  fp.UpvotesForPost,
  fp.LinkTypeName,
  fp.RelatedPostId,
  fp.OwnerDisplayName,
  fp.LastEditorDisplayName,
  fp.LastEditDate,
  fp.PostsByOwner
FROM FinalPick fp
ORDER BY fp.LastActivityDate DESC, fp.Score DESC
FETCH FIRST 100 ROWS ONLY;