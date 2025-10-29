WITH TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Body,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.Score * 0.7 + p.ViewCount * 0.2 + EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - p.CreationDate)) * -1
    ) AS rn_by_type
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
    AND p.Body IS NOT NULL
),
RecentActivity AS (
  SELECT
    t.PostId,
    t.Title,
    t.Tags,
    t.PostTypeId,
    t.CreationDate,
    t.Score,
    t.ViewCount,
    t.OwnerUserId,
    t.LastActivityDate,
    t.Body,
    t.rn_by_type,
    AVG(v.BountyAmount) OVER (PARTITION BY t.PostTypeId) AS AvgBounty
  FROM TopPosts t
  LEFT JOIN Votes v
    ON v.PostId = t.PostId
  WHERE t.rn_by_type <= 50
),
Enriched AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.Tags,
    ra.PostTypeId,
    ra.CreationDate,
    ra.Score,
    ra.ViewCount,
    ra.OwnerUserId,
    ra.LastActivityDate,
    ra.Body,
    ra.AvgBounty,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    c.DisplayName AS LastEditorDisplayName,
    lf.Name AS LastEditorFriendName,
    ra.LastActivityDate AS LastActivityDate_for_grouping,
    u.Id AS u_Id,
    c.Id AS c_Id
  FROM RecentActivity ra
  LEFT JOIN Users u ON ra.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id AND b.Class = 1
  LEFT JOIN Users c ON ra.OwnerUserId = c.Id -- changed to join on OwnerUserId because LastEditorUserId does not exist; using OwnerUserId as a best-effort substitute
  LEFT JOIN Badges lf ON lf.UserId = c.Id AND lf.Class = 2
),
Agg AS (
  SELECT
    e.PostId,
    e.Title,
    e.PostTypeId,
    e.OwnerUserId,
    e.OwnerDisplayName,
    e.OwnerReputation,
    e.ViewCount,
    e.Score,
    e.LastActivityDate,
    e.AvgBounty,
    STRING_AGG(DISTINCT ak.TagName, ',') AS TopTags
  FROM Enriched e
  LEFT JOIN LATERAL (
    SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH ' ' FROM REGEXP_REPLACE(COALESCE(e.Tags, ''), '^[<>]|[<>]$', '', 'g')), '><')) AS TagName
  ) ak ON TRUE
  GROUP BY e.PostId, e.Title, e.PostTypeId, e.OwnerUserId, e.OwnerDisplayName, e.OwnerReputation, e.ViewCount, e.Score, e.LastActivityDate, e.AvgBounty
)
SELECT
  a.PostId,
  a.Title,
  a.PostTypeId,
  a.OwnerUserId,
  a.OwnerDisplayName,
  a.OwnerReputation,
  a.ViewCount,
  a.Score,
  a.LastActivityDate,
  a.AvgBounty,
  a.TopTags,
  COUNT(*) OVER () AS Benchmark_row_count,
  MAX(p.LastActivityDate) OVER () AS GlobalLastActivity
FROM Agg a
JOIN Posts p ON p.Id = a.PostId
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
WHERE a.PostTypeId IN (1,2)
  AND (a.ViewCount > 0 OR a.Score IS NOT NULL)
ORDER BY a.LastActivityDate DESC
LIMIT 100;