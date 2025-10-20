SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.Tags,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(DISTINCT a.Id) AS AnswerCount,
  AVG(v.Value) AS AvgLast24HoursUpvotesPerHour
FROM
  Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Posts a ON a.ParentId = p.Id
  LEFT JOIN (
    SELECT
      v.PostId,
      SUM(CASE WHEN vt.Name = 'up' OR vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS Value
    FROM
      Votes v
      JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE
      v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '24' HOUR
    GROUP BY
      v.PostId
  ) v ON v.PostId = p.Id
WHERE
  p.PostTypeId = 1
  AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY
GROUP BY
  p.Id, p.Title, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId, u.DisplayName
ORDER BY
  p.Score DESC, p.ViewCount DESC
LIMIT 100;