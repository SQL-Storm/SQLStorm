-- {"query": "14061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 824}
WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, p.Body, p.Tags, CASE WHEN p.PostTypeId = 1 THEN (
    SELECT COUNT(DISTINCT v.Id)
    FROM Votes v
    WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
  ) ELSE NULL END AS VoteCount
  FROM Posts p
),
agg_cte AS (
  SELECT Id, PostTypeId, ParentId, CreationDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount, ClosedDate, CommunityOwnedDate, Body, Tags, 
    CASE WHEN PostTypeId = 1 THEN
      (SELECT SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE -1 END) FROM Votes WHERE PostId = cte.Id)
    ELSE NULL END AS NetVotes
  FROM cte
),
link_cte AS (
  SELECT p.Id, 
    COALESCE(
      (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1), 
      0
    ) AS LinkedCount,
    COALESCE(
      (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3),
      0  
    ) AS DuplicateCount
  FROM Posts p
)
SELECT
  ac.Id,
  ac.PostTypeId,
  ac.ParentId,
  ac.CreationDate,
  ac.Score,
  ac.ViewCount,
  ac.AnswerCount,
  ac.CommentCount,
  ac.FavoriteCount,
  ac.ClosedDate,
  ac.CommunityOwnedDate,
  TRIM(REPLACE(ac.Body, '<p>', '')) AS Body,
  STRING_AGG(DISTINCT TRIM(t.TagName), '><') AS Tags,
  ac.NetVotes,
  lc.LinkedCount,
  lc.DuplicateCount
FROM agg_cte ac
LEFT JOIN link_cte lc ON ac.Id = lc.Id
LEFT JOIN (
  SELECT PostId, STRING_AGG(TagName, '><') AS TagNames 
  FROM Posts p
  CROSS APPLY STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') t
  GROUP BY PostId
) t ON ac.Id = t.PostId
GROUP BY
  ac.Id,
  ac.PostTypeId,
  ac.ParentId,
  ac.CreationDate,
  ac.Score,
  ac.ViewCount,
  ac.AnswerCount,
  ac.CommentCount,
  ac.FavoriteCount,
  ac.ClosedDate,
  ac.CommunityOwnedDate,
  ac.Body,
  ac.NetVotes,
  lc.LinkedCount,
  lc.DuplicateCount
ORDER BY ac.Id;
