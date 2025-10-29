-- {"query": "5405.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 631} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerName,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.ViewCount DESC,
        p.Score DESC,
        p.CreationDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
),
RecentActivity AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeId,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    rp.OwnerUserId,
    rp.OwnerName,
    rp.Tags,
    rp.LastActivityDate,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ContentLicense,
    rp.Reputation,
    ROW_NUMBER() OVER (
      PARTITION BY rp.PostTypeId
      ORDER BY rp.LastActivityDate DESC, rp.Score DESC
    ) AS rn2
  FROM RankedPosts rp
  WHERE rp.LastActivityDate IS NOT NULL
),
Filtered AS (
  SELECT
    ra.PostId, ra.Title, ra.PostTypeId, ra.CreationDate, ra.ViewCount, ra.Score,
    ra.OwnerUserId, ra.OwnerName, ra.Tags, ra.LastActivityDate, ra.AnswerCount,
    ra.CommentCount, ra.FavoriteCount, ra.ContentLicense, ra.Reputation
  FROM RecentActivity ra
  WHERE ra.rn2 = 1
)
SELECT
  f.PostId,
  f.Title,
  CASE
    WHEN f.PostTypeId = 1 THEN 'Question'
    WHEN f.PostTypeId = 2 THEN 'Answer'
  END AS PostKind,
  f.CreationDate,
  f.LastActivityDate,
  f.ViewCount,
  f.Score,
  f.AnswerCount,
  f.CommentCount,
  f.FavoriteCount,
  f.Tags,
  f.ContentLicense,
  f.Reputation,
  f.OwnerName
FROM Filtered f
LEFT JOIN PostLinks pl ON pl.PostId = f.PostId
LEFT JOIN Posts linked ON linked.Id = pl.RelatedPostId
LEFT JOIN PostHistory ph ON ph.PostId = f.PostId
WHERE
  (pl.LinkTypeId = 1 OR pl.LinkTypeId IS NULL) -- Linked or no link
  AND (ph.Id IS NULL OR ph.PostId = f.PostId)
ORDER BY f.LastActivityDate DESC, f.Score DESC
LIMIT 100;