-- {"query": "5510.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 727} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Tags,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.AccountId,
    -- Row_number by activity, with NULL-safe ordering
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.LastActivityDate DESC NULLS LAST, p.ViewCount DESC NULLS LAST, p.Score DESC NULLS LAST
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers only
),
Filtered AS (
  SELECT
    r.*,
    -- A correlated subquery computing a complex metric: sum of upvotes minus downvotes across related posts
    (
      SELECT COALESCE(SUM(v.BountyAmount), 0)
      FROM Votes v
      WHERE v.PostId = r.Id
        AND v.VoteTypeId IN (2, 3) -- UpMod / DownMod
    ) AS UpDownBalanceFromVotes
  FROM RankedPosts r
  WHERE r.rn <= 50
),
Aggregated AS (
  SELECT
    f.Id,
    f.Title,
    f.Score,
    f.ViewCount,
    f.CreationDate,
    f.LastActivityDate,
    f.OwnerUserId,
    f.OwnerDisplayName,
    f.Reputation,
    f.Location,
    f.Tags,
    f.AcceptedAnswerId,
    f.ParentId,
    f.CommentCount,
    f.FavoriteCount,
    f.ContentLicense,
    f.UpDownBalanceFromVotes,
    -- Window function: rank within each day bucket of CreationDate
    DENSE_RANK() OVER (
      PARTITION BY DATE(f.CreationDate)
      ORDER BY f.Score DESC, f.ViewCount DESC
    ) AS DailyRank
  FROM Filtered f
  ORDER BY f.LastActivityDate DESC NULLS LAST
)
SELECT
  a.Id,
  a.Title,
  a.Score,
  a.ViewCount,
  a.CreationDate,
  a.LastActivityDate,
  a.OwnerUserId,
  a.OwnerDisplayName,
  a.Reputation,
  a.Location,
  a.Tags,
  a.AcceptedAnswerId,
  a.ParentId,
  a.CommentCount,
  a.FavoriteCount,
  a.ContentLicense,
  a.UpDownBalanceFromVotes,
  a.DailyRank,
  -- Complex computed column: a safety check combining NULLs and arithmetic
  (COALESCE(a.Score,0) * 1.0 / NULLIF((COALESCE(a.ViewCount,0) + 1), 0)) AS ScorePerView
FROM Aggregated a
WHERE a.DailyRank <= 10
  AND (a.Reputation IS NULL OR a.Reputation > 0)
  AND (a.Location IS NULL OR a.Location <> '')
ORDER BY a.DailyRank, a.LastActivityDate DESC NULLS LAST;