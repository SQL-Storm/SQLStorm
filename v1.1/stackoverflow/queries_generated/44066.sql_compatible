WITH recent_posts AS (
  SELECT p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.LastActivityDate
  FROM Posts p
  WHERE p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
    AND p.PostTypeId IN (1, 2)
  ORDER BY p.LastActivityDate DESC
  LIMIT 10000
),
active_users AS (
  SELECT u.Id, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
  FROM Users u
  WHERE u.LastAccessDate >= (CAST('2024-10-01' AS date) - INTERVAL '7' DAY)
    AND u.Reputation >= 1000
  ORDER BY u.Reputation DESC
  LIMIT 1000
),
post_comments AS (
  SELECT c.PostId, COUNT(*) AS comment_count
  FROM Comments c
  WHERE c.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
  GROUP BY c.PostId
),
post_votes AS (
  SELECT v.PostId, COUNT(*) AS vote_count
  FROM Votes v
  WHERE v.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
    AND v.VoteTypeId IN (2, 3)
  GROUP BY v.PostId
)
SELECT
  rp.Id AS post_id,
  rp.PostTypeId,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.OwnerUserId,
  rp.LastActivityDate,
  COALESCE(pc.comment_count, 0) AS comment_count,
  COALESCE(pv.vote_count, 0) AS vote_count,
  au.Id AS user_id,
  au.Reputation,
  au.CreationDate AS user_creation_date,
  au.LastAccessDate,
  au.UpVotes,
  au.DownVotes
FROM recent_posts rp
LEFT JOIN post_comments pc ON rp.Id = pc.PostId
LEFT JOIN post_votes pv ON rp.Id = pv.PostId
LEFT JOIN active_users au ON rp.OwnerUserId = au.Id
GROUP BY
  rp.Id,
  rp.PostTypeId,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.OwnerUserId,
  rp.LastActivityDate,
  pc.comment_count,
  pv.vote_count,
  au.Id,
  au.Reputation,
  au.CreationDate,
  au.LastAccessDate,
  au.UpVotes,
  au.DownVotes
ORDER BY rp.LastActivityDate DESC;