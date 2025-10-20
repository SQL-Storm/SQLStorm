WITH recent_posts AS (
  SELECT p.Id, p.PostTypeId, p.CreationDate, p.LastActivityDate, p.OwnerUserId, u.Reputation, p.Tags
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR
),
popular_tags AS (
  SELECT t.TagName, t.Count
  FROM Tags t
  ORDER BY t.Count DESC
  LIMIT 20
),
post_votes AS (
  SELECT v.PostId, COUNT(*) AS vote_count
  FROM Votes v
  WHERE v.VoteTypeId IN (2, 3)
  GROUP BY v.PostId
)
SELECT
  rp.Id AS post_id,
  rp.PostTypeId,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.Reputation AS owner_reputation,
  pt.TagName,
  pt.Count AS tag_count,
  pv.vote_count
FROM recent_posts rp
JOIN popular_tags pt ON POSITION(CONCAT('<', pt.TagName, '>') IN COALESCE(rp.Tags, '')) > 0
LEFT JOIN post_votes pv ON rp.Id = pv.PostId
GROUP BY
  rp.Id,
  rp.PostTypeId,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.Reputation,
  rp.Tags,
  pt.TagName,
  pt.Count,
  pv.vote_count
ORDER BY rp.LastActivityDate DESC, pv.vote_count DESC
LIMIT 1000;