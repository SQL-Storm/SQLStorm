WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (
      ORDER BY p.ViewCount DESC,
               p.Score DESC,
               p.AnswerCount DESC,
               p.CreationDate DESC
    ) AS rn
  FROM Posts AS p
  JOIN Users AS u
    ON p.OwnerUserId = u.Id
  WHERE
    p.PostTypeId = 1 AND p.ClosedDate IS NULL
), AggregatedPostData AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.OwnerDisplayName,
    (
      SELECT
        COUNT(c.Id)
      FROM Comments AS c
      WHERE
        c.PostId = rp.PostId
    ) AS CommentCount,
    (
      SELECT
        COUNT(ph.Id)
      FROM PostHistory AS ph
      WHERE
        ph.PostId = rp.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) AS EditCount
  FROM RankedPosts AS rp
  WHERE
    rp.rn <= 1000
)
SELECT
  apd.PostId,
  apd.Title,
  apd.CreationDate,
  apd.Score,
  apd.ViewCount,
  apd.AnswerCount,
  apd.OwnerDisplayName,
  apd.CommentCount,
  apd.EditCount,
  AVG(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56') - apd.CreationDate) / 60.0) OVER () AS AvgMinutesSinceCreation,
  COUNT(*) OVER () AS TotalPostsConsidered
FROM AggregatedPostData AS apd
ORDER BY
  apd.ViewCount DESC
LIMIT 100;