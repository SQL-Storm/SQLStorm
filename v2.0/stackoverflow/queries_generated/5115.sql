-- {"query": "5115.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 741} 
WITH TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.OwnerDisplayName,
    p.CommentCount,
    p.FavoriteCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
EnhancedPosts AS (
  SELECT
    tp.PostId,
    tp.Title,
    tp.CreationDate,
    tp.Score,
    tp.ViewCount,
    tp.Tags,
    tp.OwnerUserId,
    tp.LastActivityDate,
    tp.PostTypeId,
    tp.OwnerDisplayName,
    tp.CommentCount,
    tp.FavoriteCount,
    tp.AcceptedAnswerId,
    tp.ParentId,
    tp.ContentLicense,
    u.Reputation,
    u.DisplayName AS UserDisplayName,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccess,
    b.Name AS BadgeName,
    vts.Name AS VoteTypeName,
    vt.CreationDate AS VoteDate,
    vt.BountyAmount
  FROM TopPosts tp
  LEFT JOIN Users u ON tp.OwnerUserId = u.Id
  LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1 -- Gold badges as potential signal
  LEFT JOIN Votes vt ON vt.PostId = tp.PostId
  LEFT JOIN VoteTypes vts ON vt.VoteTypeId = vts.Id
  WHERE tp.rn = 1
),
CorrelationCTE AS (
  SELECT
    ep.PostId,
    ep.Title,
    ep.ViewCount,
    ep.Score,
    ep.Reputation,
    ep.UserDisplayName,
    ep.BadgeName,
    ep.VoteTypeName,
    ep.BountyAmount,
    COUNT(DISTINCT a.Id) AS AnswerCount,
    AVG(COALESCE(vt.BountyAmount, 0)) OVER (PARTITION BY ep.PostId) AS AvgBounty
  FROM EnhancedPosts ep
  LEFT JOIN Posts a ON a.ParentId = ep.PostId AND a.PostTypeId = 2
  LEFT JOIN Votes vt ON vt.PostId = ep.PostId
  GROUP BY
    ep.PostId,
    ep.Title,
    ep.ViewCount,
    ep.Score,
    ep.Reputation,
    ep.UserDisplayName,
    ep.BadgeName,
    ep.VoteTypeName,
    ep.BountyAmount
),
Windowed AS (
  SELECT
    c.*,
    ROW_NUMBER() OVER (ORDER BY c.Score DESC, c.ViewCount DESC, c.AvgBounty DESC NULLS LAST) AS rn
  FROM CorrelationCTE c
)
SELECT
  w.PostId,
  w.Title,
  w.ViewCount,
  w.Score,
  w.Reputation AS UserReputation,
  w.UserDisplayName,
  w.BadgeName,
  w.VoteTypeName,
  w.BountyAmount,
  w.AnswerCount,
  w.AvgBounty
FROM Windowed w
WHERE w.rn <= 100
ORDER BY w.Score DESC, w.ViewCount DESC, w.AvgBounty DESC NULLS LAST
;