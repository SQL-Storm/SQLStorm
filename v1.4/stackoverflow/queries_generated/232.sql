-- {"query": "232.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 12366} 
WITH
  post_activity AS (
    SELECT Id, COALESCE(LastActivityDate, CreationDate) AS ActivityDate
    FROM Posts
  ),
  daily_votes AS (
    SELECT v.PostId, date_trunc('day', v.CreationDate) AS vote_day,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                    WHEN v.VoteTypeId = 3 THEN -1
                    ELSE 0 END) AS delta
    FROM Votes v
    GROUP BY v.PostId, vote_day
  ),
  latest_comment AS (
    SELECT c1.PostId, c1.Text, c1.CreationDate
    FROM Comments c1
    WHERE c1.Id = (
      SELECT c2.Id
      FROM Comments c2
      WHERE c2.PostId = c1.PostId
      ORDER BY c2.CreationDate DESC
      LIMIT 1
    )
  ),
  post_tags AS (
    SELECT p.Id AS PostId,
           string_agg(t.tagname, ',') FILTER (WHERE tg.TagName IS NOT NULL) AS TagsList
    FROM Posts p
    LEFT JOIN LATERAL unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) AS t(tagname) ON TRUE
    LEFT JOIN Tags tg ON tg.TagName = t.tagname
    GROUP BY p.Id
  ),
  top_score AS (
    SELECT p.Id AS Id, p.Title, p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName AS OwnerName,
           pa.ActivityDate, lc.Text AS LatestComment, lc.CreationDate AS CommentDate, ps.TagsList,
           (p.Score + COALESCE(dv.delta, 0) + COALESCE(LENGTH(ps.TagsList), 0)) AS Composite
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN post_activity pa ON pa.Id = p.Id
    LEFT JOIN daily_votes dv ON dv.PostId = p.Id
    LEFT JOIN latest_comment lc ON lc.PostId = p.Id
    LEFT JOIN post_tags ps ON ps.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.Score > -5
    ORDER BY Composite DESC
    LIMIT 200
  ),
  top_recent AS (
    SELECT p.Id AS Id, p.Title, p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName AS OwnerName,
           pa.ActivityDate, lc.Text AS LatestComment, lc.CreationDate AS CommentDate, ps.TagsList,
           (p.Score + COALESCE(dv.delta, 0) + COALESCE(LENGTH(ps.TagsList), 0) +
            COALESCE(EXTRACT(EPOCH FROM pa.ActivityDate) / 3600.0, 0)) AS Composite
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN post_activity pa ON pa.Id = p.Id
    LEFT JOIN daily_votes dv ON dv.PostId = p.Id
    LEFT JOIN latest_comment lc ON lc.PostId = p.Id
    LEFT JOIN post_tags ps ON ps.PostId = p.Id
    WHERE p.PostTypeId = 1
    ORDER BY Composite DESC
    LIMIT 200
  )
SELECT *
FROM (
  SELECT Id, Title, Score, ViewCount, OwnerUserId, OwnerName, ActivityDate, LatestComment, CommentDate, TagsList, Composite,
         ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY Composite DESC) AS rn
  FROM top_score
  UNION ALL
  SELECT Id, Title, Score, ViewCount, OwnerUserId, OwnerName, ActivityDate, LatestComment, CommentDate, TagsList, Composite,
         ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY Composite DESC) AS rn
  FROM top_recent
) q
WHERE rn <= 5
ORDER BY OwnerUserId, Composite DESC;