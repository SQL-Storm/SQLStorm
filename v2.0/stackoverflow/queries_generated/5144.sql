-- {"query": "5144.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 817} 
WITH Trending AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY
        p.ViewCount * 0.6 + p.Score * 1.2 + p.CommentCount * 0.4 DESC,
        p.CreationDate DESC
    ) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
Engagement AS (
  SELECT
    t.PostId,
    t.Title,
    t.CreationDate,
    t.OwnerUserId,
    t.Tags,
    t.ViewCount,
    t.Score,
    t.CommentCount,
    t.AnswerCount,
    SUM(COALESCE(v.BountyAmount,0)) AS BountyTotal,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
    SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes
  FROM Trending t
  LEFT JOIN Votes v ON v.PostId = t.PostId
  GROUP BY
    t.PostId, t.Title, t.CreationDate, t.OwnerUserId, t.Tags, t.ViewCount,
    t.Score, t.CommentCount, t.AnswerCount
),
TopAuthors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.FollowerCount := (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1),
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS rn
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
Filtered AS (
  SELECT
    e.PostId,
    e.Title,
    e.CreationDate,
    e.OwnerUserId,
    e.Tags,
    e.ViewCount,
    e.Score,
    e.CommentCount,
    e.AnswerCount,
    e.BountyTotal,
    e.Upvotes,
    e.Downvotes,
    e.CloseVotes,
    ta.DisplayName AS OwnerDisplayName,
    ta.Reputation AS OwnerReputation,
    U1.Login AS LastEditorLogin
  FROM Engagement e
  LEFT JOIN Users ta ON ta.Id = e.OwnerUserId
  LEFT JOIN (
    SELECT Id, DisplayName, Reputation, Login
    FROM (
      SELECT u.Id, u.DisplayName AS DisplayName, u.Reputation, u.EmailHash
      FROM Users u
    ) AS sub1
  ) AS U1 ON U1.Id = e.OwnerUserId
)
SELECT
  p.PostId,
  p.Title,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.CommentCount,
  p.AnswerCount,
  p.Tags,
  p.OwnerUserId,
  u.DisplayName AS OwnerName,
  u.Reputation AS OwnerReputation,
  e.BountyTotal,
  e.Upvotes,
  e.Downvotes,
  e.CloseVotes,
  u2.LastAccessDate AS LastActivity,
  pc.Name AS PostCategory
FROM Posts p
JOIN Filtered e ON e.PostId = p.Id
LEFT JOIN Users u ON u.Id = p.OwnerUserId
LEFT JOIN PostTypes pc ON pc.Id = p.PostTypeId
ORDER BY e.BountyTotal DESC, e.Upvotes - e.Downvotes DESC, p.CreationDate DESC
LIMIT 100;