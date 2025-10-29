WITH top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    NULL AS CloseReasonId
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365' DAY
),
tag_expansions AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    array_agg(DISTINCT pw.Id) AS QuestionIds
  FROM Tags t
  LEFT JOIN Posts pw ON pw.Tags LIKE '%' || t.TagName || '%'
  WHERE t.IsModeratorOnly = false OR t.IsModeratorOnly IS NULL
  GROUP BY t.Id, t.TagName
),
recent_comments AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCountLast30
  FROM Comments c
  WHERE c.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY
  GROUP BY c.PostId
),
hist AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180' DAY
),
agg AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.CreationDate AS PostCreationDate,
    tq.ViewCount,
    tq.Score,
    tq.Tags,
    tq.OwnerUserId,
    tq.LastActivityDate,
    COALESCE(rc.CommentCountLast30, 0) AS RecentComments,
    CASE WHEN COALESCE(hs.Closed, 0) = 1 THEN TRUE ELSE FALSE END AS IsClosed,
    hs.CloseReasonId,
    COALESCE(be.TotalBounties, 0) AS TotalBounties
  FROM top_questions tq
  LEFT JOIN recent_comments rc ON rc.PostId = tq.PostId
  LEFT JOIN (
    SELECT
      ph.PostId,
      MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS Closed,
      MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS CloseReasonId
    FROM PostHistory ph
    GROUP BY ph.PostId
  ) hs ON hs.PostId = tq.PostId
  LEFT JOIN (
    SELECT
      v.PostId,
      SUM(v.BountyAmount) AS TotalBounties
    FROM Votes v
    WHERE v.VoteTypeId = 8
    GROUP BY v.PostId
  ) be ON be.PostId = tq.PostId
)
SELECT
  agg.PostId,
  agg.Title,
  agg.PostCreationDate,
  agg.ViewCount,
  agg.Score,
  REPLACE(agg.Tags, ' ', '') AS TagList,
  agg.OwnerUserId,
  agg.LastActivityDate,
  agg.RecentComments,
  CASE WHEN agg.IsClosed THEN 'Closed' ELSE 'Open' END AS Status,
  agg.CloseReasonId,
  agg.TotalBounties,
  (agg.ViewCount * 0.5) + (agg.Score * 2) + (agg.RecentComments * 3) AS BenchmarkScore
FROM agg
ORDER BY BenchmarkScore DESC
LIMIT 100;