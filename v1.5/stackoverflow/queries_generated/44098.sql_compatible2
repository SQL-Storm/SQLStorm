WITH recent_posts AS (
  SELECT p.Id, p.PostTypeId, p.CreationDate, p.LastActivityDate, p.OwnerUserId, u.Reputation,
         p.Tags
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate >= TIMESTAMP '2023-10-01 12:34:56' - INTERVAL '1 year'
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
JOIN popular_tags pt ON POSITION(pt.TagName IN rp.Tags) > 0
LEFT JOIN post_votes pv ON rp.Id = pv.PostId
ORDER BY rp.LastActivityDate DESC NULLS LAST, COALESCE(pv.vote_count, 0) DESC
LIMIT 1000;