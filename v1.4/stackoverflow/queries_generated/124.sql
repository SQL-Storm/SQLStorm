-- {"query": "124.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2113} 
WITH recent_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.CreationDate >= now() - interval '1 year'
),
author_stats AS (
  SELECT
    u.Id AS UserId,
    COALESCE(u.DisplayName, 'Unknown') AS DisplayName,
    u.Reputation,
    MAX(p.LastActivityDate) AS last_activity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
post_zoom AS (
  SELECT
    rp.Id AS PostId,
    rp.Title,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.PostTypeId,
    rp.Score,
    rp.ViewCount,
    rp.LastActivityDate,
    COALESCE(a.DisplayName, 'Unknown') AS AuthorName,
    a.Reputation AS AuthorReputation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 8) AS BountyTotal
  FROM recent_posts rp
  LEFT JOIN author_stats a ON a.UserId = rp.OwnerUserId
  WHERE rp.rn <= 5
)
SELECT
  pz.PostId,
  pz.Title,
  pz.CreationDate,
  pz.AuthorName,
  pz.AuthorReputation,
  pz.PostTypeId,
  pz.Score,
  pz.ViewCount,
  pz.CommentCount,
  pz.UpVotes,
  pz.DownVotes,
  pz.BountyTotal
FROM post_zoom pz
ORDER BY pz.CreationDate DESC
LIMIT 100;