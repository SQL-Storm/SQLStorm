-- {"query": "4527.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 926} 

WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate AS PostCreationDate,
    pt.Name AS PostTypeName,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts AS p
  JOIN PostTypes AS pt
    ON p.PostTypeId = pt.Id
  WHERE
    p.OwnerUserId IS NOT NULL AND p.Score > 0
), PostActivity AS (
  SELECT
    p.Id AS PostId,
    COUNT(c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    MAX(p.LastActivityDate) AS LastPostActivity
  FROM Posts AS p
  LEFT JOIN Comments AS c
    ON p.Id = c.PostId
  LEFT JOIN Votes AS v
    ON p.Id = v.PostId
  GROUP BY
    p.Id
), UserReputation AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    (
      SELECT
        COUNT(*)
      FROM Badges AS b
      WHERE
        b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadgeCount,
    (
      SELECT
        COUNT(*)
      FROM Badges AS b
      WHERE
        b.UserId = u.Id AND b.Class = 2
    ) AS SilverBadgeCount,
    (
      SELECT
        COUNT(*)
      FROM Badges AS b
      WHERE
        b.UserId = u.Id AND b.Class = 3
    ) AS BronzeBadgeCount
  FROM Users AS u
)
SELECT
  rp.PostId,
  rp.Title,
  rp.PostTypeName,
  rp.PostCreationDate,
  pa.CommentCount,
  pa.UpVoteCount,
  pa.DownVoteCount,
  pa.LastPostActivity,
  ur.DisplayName AS OwnerDisplayName,
  ur.Reputation,
  ur.UserCreationDate,
  ur.GoldBadgeCount,
  ur.SilverBadgeCount,
  ur.BronzeBadgeCount,
  CASE
    WHEN ur.Reputation > 10000 THEN 'High Reputation'
    WHEN ur.Reputation BETWEEN 1000 AND 10000 THEN 'Medium Reputation'
    ELSE 'Low Reputation'
  END AS ReputationLevel,
  COALESCE(ur.DisplayName, 'Unknown User') AS DisplayNameOrUnknown,
  CASE
    WHEN rp.PostCreationDate < DATE('now', '-1 year') AND pa.LastPostActivity < DATE('now', '-6 months') THEN 'Stale'
    ELSE 'Active'
  END AS PostStatus
FROM RankedPosts AS rp
JOIN PostActivity AS pa
  ON rp.PostId = pa.PostId
LEFT JOIN UserReputation AS ur
  ON rp.OwnerUserId = ur.UserId
WHERE
  rp.rn <= 100 AND ur.Reputation > 50
UNION ALL
SELECT
  NULL,
  '--- Summary ---',
  NULL,
  NULL,
  COUNT(pa.CommentCount),
  SUM(pa.UpVoteCount),
  SUM(pa.DownVoteCount),
  NULL,
  NULL,
  AVG(ur.Reputation),
  NULL,
  NULL,
  NULL,
  'Overall Average',
  NULL,
  NULL
FROM RankedPosts AS rp
JOIN PostActivity AS pa
  ON rp.PostId = pa.PostId
LEFT JOIN UserReputation AS ur
  ON rp.OwnerUserId = ur.UserId
WHERE
  rp.rn <= 100 AND ur.Reputation > 50
ORDER BY
  rp.PostId;
