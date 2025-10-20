-- {"query": "239.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 8762} 
SELECT UserId, DisplayName, Reputation, LastActivityDate, PostId, PostTitle, PostTypeId, TotalCommentCount, TagList, rn
FROM (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    p.LastActivityDate AS LastActivityDate,
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.PostTypeId AS PostTypeId,
    COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 0) AS TotalCommentCount,
    (
      SELECT string_agg(DISTINCT tname, ',')
      FROM (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tname
      ) t
    ) AS TagList,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate IS NOT NULL AND p.LastActivityDate >= NOW() - INTERVAL '1 year'
) AS t1
WHERE rn = 1

UNION ALL

SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  NULL AS LastActivityDate,
  NULL AS PostId,
  NULL AS PostTitle,
  NULL AS PostTypeId,
  0 AS TotalCommentCount,
  NULL AS TagList,
  0 AS rn
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING MAX(p.LastActivityDate) IS NULL

ORDER BY Reputation DESC, UserId ASC;