WITH
RecentActive AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.ClosedDate IS NULL
    AND p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
PopularQuestions AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    ra.LastActivityDate,
    ra.ViewCount,
    ra.Score,
    ra.Tags,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ra.PostId AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ra.PostId AND v.VoteTypeId = 3) AS Downvotes
  FROM RecentActive ra
  JOIN Users u ON u.Id = ra.OwnerUserId
  WHERE ra.rn <= 5
),
CrossLinked AS (
  SELECT
    pq.PostId,
    pq.Title,
    pq.OwnerUserId,
    pq.OwnerDisplayName,
    pq.LastActivityDate,
    pq.ViewCount,
    pq.Score,
    pq.Tags,
    pq.Upvotes,
    pq.Downvotes,
    COALESCE(c.CloseReason, NULL) AS CloseReason
  FROM PopularQuestions pq
  LEFT JOIN (
    SELECT
      ph.PostId,
      ph.Comment -- contains CloseReasonId for close events
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
  ) phc ON phc.PostId = pq.PostId
  LEFT JOIN LATERAL (
    SELECT ct.Name AS CloseReason
    FROM PostHistory ph2
    JOIN CloseReasonTypes ct ON CAST(ph2.Comment AS SMALLINT) = ct.Id
    WHERE ph2.PostId = pq.PostId
      AND ph2.PostHistoryTypeId = 10
    ORDER BY ph2.CreationDate DESC
    LIMIT 1
  ) c ON true
),
TaggedWithLinks AS (
  SELECT
    c.PostId,
    c.Title,
    c.OwnerUserId,
    c.OwnerDisplayName,
    c.LastActivityDate,
    c.ViewCount,
    c.Score,
    c.Tags,
    c.Upvotes,
    c.Downvotes,
    c.CloseReason,
    COALESCE(ln.LinkCount, 0) AS RelatedLinks
  FROM CrossLinked c
  LEFT JOIN (
    SELECT PId.PostId, COUNT(*) AS LinkCount
    FROM PostLinks PId
    WHERE PId.LinkTypeId = 1
    GROUP BY PId.PostId
  ) ln ON ln.PostId = c.PostId
),
Aggregated AS (
  SELECT
    pt.PostTypeName,
    t.PostId,
    t.Title,
    t.OwnerDisplayName,
    t.LastActivityDate,
    t.ViewCount,
    t.Score,
    t.Tags,
    t.Upvotes,
    t.Downvotes,
    t.CloseReason,
    t.RelatedLinks,
    CASE
      WHEN t.ViewCount > 1000 THEN 'Very High'
      WHEN t.ViewCount > 500 THEN 'High'
      ELSE 'Moderate'
    END AS PopularityBucket
  FROM TaggedWithLinks t
  JOIN (
    SELECT 1 AS Id, 'Question' AS PostTypeName
    UNION ALL SELECT 2, 'Answer'
  ) pt ON pt.Id = 1
)
SELECT
  a.PostTypeName,
  a.PostId,
  a.Title,
  a.OwnerDisplayName,
  a.LastActivityDate,
  a.ViewCount,
  a.Score,
  a.Tags,
  a.Upvotes,
  a.Downvotes,
  a.CloseReason,
  a.RelatedLinks,
  a.PopularityBucket
FROM Aggregated a
GROUP BY
  a.PostTypeName,
  a.PostId,
  a.Title,
  a.OwnerDisplayName,
  a.LastActivityDate,
  a.ViewCount,
  a.Score,
  a.Tags,
  a.Upvotes,
  a.Downvotes,
  a.CloseReason,
  a.RelatedLinks,
  a.PopularityBucket
ORDER BY a.LastActivityDate DESC, a.PopularityBucket, a.Score DESC
LIMIT 100;