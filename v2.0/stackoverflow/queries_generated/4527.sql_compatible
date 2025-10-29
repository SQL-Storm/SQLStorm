WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate AS PostCreationDate,
    pt.Name AS PostTypeName,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  JOIN PostTypes pt
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
  FROM Posts p
  LEFT JOIN Comments c
    ON p.Id = c.PostId
  LEFT JOIN Votes v
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
      SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadgeCount,
    (
      SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2
    ) AS SilverBadgeCount,
    (
      SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3
    ) AS BronzeBadgeCount
  FROM Users u
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
    WHEN rp.PostCreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year') AND pa.LastPostActivity < (cast('2024-10-01' as date) - INTERVAL '6 months') THEN 'Stale'
    ELSE 'Active'
  END AS PostStatus
FROM RankedPosts rp
JOIN PostActivity pa
  ON rp.PostId = pa.PostId
LEFT JOIN UserReputation ur
  ON rp.OwnerUserId = ur.UserId
WHERE
  rp.rn <= 100 AND ur.Reputation > 50

UNION ALL

SELECT
  NULL AS PostId,
  '--- Summary ---' AS Title,
  NULL AS PostTypeName,
  NULL AS PostCreationDate,
  COUNT(pa.CommentCount) AS CommentCount,
  SUM(pa.UpVoteCount) AS UpVoteCount,
  SUM(pa.DownVoteCount) AS DownVoteCount,
  NULL AS LastPostActivity,
  NULL AS OwnerDisplayName,
  AVG(ur.Reputation) AS Reputation,
  NULL AS UserCreationDate,
  NULL AS GoldBadgeCount,
  NULL AS SilverBadgeCount,
  NULL AS BronzeBadgeCount,
  'Overall Average' AS ReputationLevel,
  NULL AS DisplayNameOrUnknown,
  NULL AS PostStatus
FROM RankedPosts rp
JOIN PostActivity pa
  ON rp.PostId = pa.PostId
LEFT JOIN UserReputation ur
  ON rp.OwnerUserId = ur.UserId
WHERE
  rp.rn <= 100 AND ur.Reputation > 50
ORDER BY
  PostId;