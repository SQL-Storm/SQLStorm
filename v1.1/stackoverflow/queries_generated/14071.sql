-- {"query": "14071.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 168120, "output_tokens": 71920} 
WITH cte AS (
  SELECT 
    p.Id AS PostId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    CASE 
      WHEN p.PostTypeId = 1 THEN 'Question'
      WHEN p.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostType,
    CASE
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
      WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
      ELSE 'Open'
    END AS PostStatus,
    CASE
      WHEN ph.PostHistoryTypeId IN (10, 11, 19, 20) THEN ph.Comment
      WHEN ph.PostHistoryTypeId IN (33, 34) THEN (SELECT Name FROM PostNotices WHERE Id = CAST(ph.Comment AS INT))
      ELSE NULL
    END AS PostStatusReason,
    LEAD(ph.CreationDate, 1, NULL) OVER (PARTITION BY p.Id ORDER BY ph.CreationDate) AS NextPostHistoryDate,
    LEAD(ph.PostHistoryTypeId, 1, NULL) OVER (PARTITION BY p.Id ORDER BY ph.CreationDate) AS NextPostHistoryTypeId
  FROM Posts p
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId
  WHERE p.PostTypeId IN (1, 2)
),
tag_stats AS (
  SELECT 
    Tags,
    STRING_AGG(SUBSTRING(Tags, 2, CHARINDEX('><', Tags, 2) - 2), ',') AS TagList,
    COUNT(*) AS TagCount
  FROM cte
  GROUP BY Tags
),
user_stats AS (
  SELECT
    OwnerUserId,
    COUNT(*) AS PostCount,
    SUM(Score) AS TotalScore,
    SUM(ViewCount) AS TotalViews,
    MAX(CreationDate) AS LastPostDate
  FROM cte
  GROUP BY OwnerUserId
)
SELECT
  cte.PostId,
  cte.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  cte.CreationDate,
  cte.Score,
  cte.ViewCount,
  cte.PostType,
  cte.PostStatus,
  cte.PostStatusReason,
  ts.TagList,
  ts.TagCount,
  us.PostCount AS OwnerPostCount,
  us.TotalScore AS OwnerTotalScore,
  us.TotalViews AS OwnerTotalViews,
  us.LastPostDate AS OwnerLastPostDate,
  CASE
    WHEN cte.NextPostHistoryTypeId = 10 THEN 'Closed'
    WHEN cte.NextPostHistoryTypeId = 11 THEN 'Reopened'
    WHEN cte.NextPostHistoryTypeId = 19 THEN 'Protected'
    WHEN cte.NextPostHistoryTypeId = 20 THEN 'Unprotected'
    ELSE NULL
  END AS NextPostStatusChange,
  CASE
    WHEN cte.NextPostHistoryTypeId IS NOT NULL AND cte.NextPostHistoryDate IS NOT NULL THEN DATEDIFF(SECOND, cte.CreationDate, cte.NextPostHistoryDate)
    ELSE NULL
  END AS TimeToNextStatusChange
FROM cte
LEFT JOIN Users u ON cte.OwnerUserId = u.Id
LEFT JOIN tag_stats ts ON cte.Tags = ts.Tags
LEFT JOIN user_stats us ON cte.OwnerUserId = us.OwnerUserId
ORDER BY cte.PostId;