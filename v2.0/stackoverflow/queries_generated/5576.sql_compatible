WITH
q AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    MAX(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS HasBadge
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Badges b ON b.UserId = p.OwnerUserId
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
  GROUP BY
    p.Id, p.Title, p.CreationDate, p.LastActivityDate, p.ViewCount, p.Score, p.Tags, p.OwnerUserId, u.DisplayName
),
recent AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    COALESCE(pc.CommentCount, 0) AS CommentCount,
    COALESCE(pv.VoteCount, 0) AS VoteCount,
    COALESCE(pv.UpVotes, 0) AS UpVotes,
    COALESCE(pv.DownVotes, 0) AS DownVotes,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT PostId, COUNT(DISTINCT Id) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) pc ON pc.PostId = p.Id
  LEFT JOIN (
    SELECT PostId,
           COUNT(DISTINCT Id) AS VoteCount,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ) pv ON pv.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
)
SELECT
  r.PostId,
  r.Title,
  r.CreationDate,
  r.LastActivityDate,
  r.ViewCount,
  r.Score,
  r.Tags,
  r.OwnerUserId,
  r.OwnerName,
  r.CommentCount,
  r.VoteCount,
  r.UpVotes,
  r.DownVotes
FROM recent r
JOIN LATERAL (
  SELECT
    COALESCE(pv.BountyAmount, 0) AS BountyAmount
  FROM Votes pv
  WHERE pv.PostId = r.PostId
  ORDER BY pv.CreationDate DESC
  LIMIT 1
) vb ON true
ORDER BY r.LastActivityDate DESC
LIMIT 100;