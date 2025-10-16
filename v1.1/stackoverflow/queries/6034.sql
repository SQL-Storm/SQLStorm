WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.Body,
    p.FavoriteCount,
    p.ContentLicense,
    CASE
      WHEN p.LastActivityDate >= DATE '2024-10-01' - INTERVAL '7' DAY THEN 'last_7_days'
      WHEN p.LastActivityDate >= DATE '2024-10-01' - INTERVAL '30' DAY THEN 'last_30_days'
      WHEN p.LastActivityDate >= DATE '2024-10-01' - INTERVAL '90' DAY THEN 'last_90_days'
      ELSE 'older'
    END AS activity_bucket,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId,
        CASE
          WHEN p.LastActivityDate >= DATE '2024-10-01' - INTERVAL '7' DAY THEN 'last_7_days'
          WHEN p.LastActivityDate >= DATE '2024-10-01' - INTERVAL '30' DAY THEN 'last_30_days'
          WHEN p.LastActivityDate >= DATE '2024-10-01' - INTERVAL '90' DAY THEN 'last_90_days'
          ELSE 'older'
        END
      ORDER BY p.Score DESC, p.LastActivityDate DESC
    ) AS rn_in_bucket
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN Tags t ON p.Id = t.WikiPostId
  WHERE p.PostTypeId IN (1, 2)
    AND (p.ViewCount > 0 OR p.Score > 0)
    AND (p.OwnerUserId IS NOT NULL)
),
Aggregated AS (
  SELECT
    rp.activity_bucket,
    rp.PostTypeId,
    COUNT(*) AS total_posts,
    AVG(rp.Score) AS avg_score,
    SUM(rp.ViewCount) AS total_views,
    MAX(rp.LastActivityDate) AS most_recent_activity
  FROM RankedPosts rp
  GROUP BY rp.activity_bucket, rp.PostTypeId
),
TopByBucket AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.AnswerCount,
    rp.CommentCount,
    rp.LastActivityDate,
    rp.PostTypeId,
    rp.ParentId,
    rp.AcceptedAnswerId,
    rp.LastEditorUserId,
    rp.LastEditDate,
    rp.Body,
    rp.FavoriteCount,
    rp.ContentLicense,
    rp.activity_bucket,
    rp.rn_in_bucket
  FROM RankedPosts rp
  WHERE rp.rn_in_bucket <= 5
)
SELECT
  b.activity_bucket,
  b.PostTypeId,
  a.total_posts,
  a.avg_score,
  a.total_views,
  b.Title,
  b.OwnerUserId,
  u.DisplayName,
  b.CreationDate,
  b.Score,
  b.ViewCount,
  b.Tags,
  b.CommentCount,
  b.LastActivityDate,
  (
    SELECT STRING_AGG(lt.Name, ',')
    FROM PostLinks pl2
    JOIN Posts p2 ON pl2.RelatedPostId = p2.Id
    JOIN LinkTypes lt ON pl2.LinkTypeId = lt.Id
    WHERE pl2.PostId = b.Id
  ) AS linked_types,
  (
    SELECT COUNT(*) FROM Votes v WHERE v.PostId = b.Id AND v.VoteTypeId = 2
  ) AS upvotes_from_votes,
  (
    SELECT COUNT(*) FROM Votes v WHERE v.PostId = b.Id AND v.VoteTypeId = 3
  ) AS downvotes_from_votes
FROM TopByBucket b
JOIN Aggregated a
  ON b.PostTypeId = a.PostTypeId
  AND b.activity_bucket = a.activity_bucket
LEFT JOIN Users u ON b.OwnerUserId = u.Id
GROUP BY
  b.activity_bucket,
  b.PostTypeId,
  a.total_posts,
  a.avg_score,
  a.total_views,
  b.Title,
  b.OwnerUserId,
  u.DisplayName,
  b.CreationDate,
  b.Score,
  b.ViewCount,
  b.Tags,
  b.CommentCount,
  b.LastActivityDate,
  b.Id,
  b.rn_in_bucket
ORDER BY b.activity_bucket, b.PostTypeId, b.rn_in_bucket;