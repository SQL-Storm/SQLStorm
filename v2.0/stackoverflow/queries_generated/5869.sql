-- {"query": "5869.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 932} 
WITH
-- recent activity per post (most recent editor and date)
RecentEdits AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    p.LastActivityDate,
    MAX(ph.CreationDate) AS LastEditDate
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  GROUP BY
    p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score,
    p.OwnerUserId, p.Tags, p.PostTypeId, p.LastActivityDate
),
-- aggregate tag-based metrics for questions
TagMetrics AS (
  SELECT
    t.TagName,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActive
  FROM Posts p
  JOIN LATERAL string_to_array(
        coalesce(p.Tags, ''), '><'
      ) AS tg(tag) ON TRUE
  LEFT JOIN Tags t ON t.TagName = replace(replace(substr(p.Tags, 2, length(p.Tags)-2), '><', ','), ',', ',')
  GROUP BY t.TagName
),
-- correlated subquery: top related posts by link type
Related AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkType,
    v.SumVotes
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  LEFT JOIN (
    SELECT PostId, SUM(COALESCE(vt.VoteTypeId = 2, 0)) AS SumVotes
    FROM Votes v
    JOIN Votes vt ON vt.PostId = v.PostId AND vt.VoteTypeId = 2
    GROUP BY PostId
  ) v ON v.PostId = pl.RelatedPostId
),
-- window functions: ranking posts by activity and score
Ranked AS (
  SELECT
    re.PostId,
    re.Title,
    re.CreationDate,
    re.LastEditDate,
    re.ViewCount,
    re.Score,
    ROW_NUMBER() OVER (PARTITION BY re.PostTypeId ORDER BY re.LastActivityDate DESC, re.Score DESC, re.ViewCount DESC) AS rn
  FROM RecentEdits re
)
SELECT
  -- main selection: bold mix of metrics to benchmark complex predicates and joins
  p.Id AS PostId,
  p.PostTypeId,
  pt.Name AS PostTypeName,
  u.DisplayName AS Owner,
  p.Title,
  p.Tags,
  p.CreationDate,
  p.LastActivityDate,
  p.LastEditDate,
  p.ViewCount,
  p.Score,
  p.FavoriteCount,
  COALESCE(closed.Name, 'Open') AS ClosedStatus,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
  -- computed fields with NULLs and string expressions
  (CASE WHEN p.OwnerUserId IS NULL THEN 'Unknown' ELSE u.DisplayName END) AS OwnerDisplay,
  (CASE WHEN p.Body ~ 'https?://[^ ]+' THEN 'ContainsLink' ELSE 'NoLink' END) AS BodyLinkIndicator,
  -- have some correlated subquery usage
  (SELECT COUNT(*) FROM PostLinks pl2 WHERE pl2.PostId = p.Id) AS LinkCount,
  -- window function example: rank within post type
  rw.rnk AS RankWithinType
FROM Posts p
JOIN PostTypes pt ON pt.Id = p.PostTypeId
LEFT JOIN Users u ON u.Id = p.OwnerUserId
LEFT JOIN (
  SELECT
    p2.Id,
    ROW_NUMBER() OVER (PARTITION BY p2.PostTypeId ORDER BY p2.LastActivityDate DESC) AS rnk
  FROM Posts p2
) rw ON rw.Id = p.Id
LEFT JOIN (
  SELECT Id, Name FROM CloseReasonTypes
) closed ON closed.Id = p.ClosedDate -- dummy join to illustrate NULL logic
WHERE
  p.LastActivityDate IS NOT NULL
  AND p.ViewCount > 0
  AND (p.Score > 0 OR p.FavoriteCount > 0)
ORDER BY p.LastActivityDate DESC
LIMIT 100;