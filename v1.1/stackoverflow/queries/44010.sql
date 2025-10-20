WITH recent_posts AS (
  SELECT p.Id, p.CreationDate, p.OwnerUserId, p.ParentId, p.PostTypeId, p.Tags, p.Title, p.ClosedDate, p.CommunityOwnedDate
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
)
SELECT
  u.DisplayName AS OwnerDisplayName,
  t.TagName,
  COUNT(rp.Id) AS PostCount,
  AVG(EXTRACT(EPOCH FROM (COALESCE(rp.ClosedDate, rp.CommunityOwnedDate, CAST('2024-10-01 12:34:56' AS TIMESTAMP)) - rp.CreationDate)) / 86400.0) AS AvgDaysTillClosed,
  ROUND(SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(rp.Id), 2) AS QuestionPct,
  ROUND(SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) * 1.0 / COUNT(rp.Id), 2) AS AnswerPct,
  ROUND(SUM(CASE WHEN rp.ParentId IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(rp.Id), 2) AS ChildPostPct
FROM recent_posts rp
JOIN Users u ON rp.OwnerUserId = u.Id
JOIN Tags t ON POSITION(t.TagName IN COALESCE(rp.Tags, '')) > 0
GROUP BY u.DisplayName, t.TagName
ORDER BY PostCount DESC
LIMIT 100;