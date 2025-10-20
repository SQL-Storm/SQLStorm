-- {"query": "303.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 24569} 
WITH
RecentQuestions AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.Body,
         p.OwnerUserId,
         p.ViewCount,
         p.Score,
         p.Tags,
         LENGTH(p.Title) AS TitleLen,
         LENGTH(p.Body) AS BodyLen,
         p.CreationDate,
         p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CURRENT_DATE - INTERVAL '180 days'
),
CommentCounts AS (
  SELECT PostId, COUNT(*) AS CommentCount
  FROM Comments
  GROUP BY PostId
),
PostStats AS (
  SELECT rq.PostId,
         rq.Title,
         rq.OwnerUserId,
         rq.ViewCount,
         rq.Score,
         rq.TitleLen,
         rq.BodyLen,
         COALESCE(cc.CommentCount, 0) AS CommentCount,
         rq.Tags
  FROM RecentQuestions rq
  LEFT JOIN CommentCounts cc ON cc.PostId = rq.PostId
),
TagsList AS (
  SELECT p.Id AS PostId,
         STRING_AGG(t.tag, ',') AS TagList
  FROM Posts p
  LEFT JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(tag) ON true
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
),
BadgeCounts AS (
  SELECT b.UserId, COUNT(*) AS BadgeCount
  FROM Badges b
  GROUP BY b.UserId
),
HistorySummary AS (
  SELECT ph.PostId, COUNT(*) AS HistoryEvents, MAX(ph.CreationDate) AS LastHistoryDate
  FROM PostHistory ph
  GROUP BY ph.PostId
),
Ranked AS (
  SELECT ps.PostId,
         ps.Title,
         ps.OwnerUserId,
         ps.ViewCount,
         ps.Score,
         ps.TitleLen,
         ps.BodyLen,
         ps.CommentCount,
         COALESCE(bc.BadgeCount, 0) AS OwnerBadgeCount,
         COALESCE(hs.HistoryEvents, 0) AS HistoryEvents,
         hs.LastHistoryDate,
         COALESCE(tl.TagList, '') AS TagList,
         (0.6 * ps.Score) + (0.2 * ps.ViewCount) + (0.15 * ps.TitleLen) + (0.05 * ps.BodyLen) AS WeightedScore
  FROM PostStats ps
  LEFT JOIN BadgeCounts bc ON bc.UserId = ps.OwnerUserId
  LEFT JOIN HistorySummary hs ON hs.PostId = ps.PostId
  LEFT JOIN TagsList tl ON tl.PostId = ps.PostId
),
OwnerTop AS (
  SELECT r.*,
         ROW_NUMBER() OVER (PARTITION BY r.OwnerUserId ORDER BY r.WeightedScore DESC, r.LastHistoryDate DESC NULLS LAST) AS rn
  FROM Ranked r
),
GlobalTop AS (
  SELECT r.*,
         ROW_NUMBER() OVER (ORDER BY r.WeightedScore DESC, r.LastHistoryDate DESC NULLS LAST) AS rn_all
  FROM Ranked r
)
SELECT
  o.PostId,
  o.Title,
  o.OwnerUserId,
  COALESCE(u.DisplayName, 'Unknown') AS OwnerDisplayName,
  o.TitleLen,
  o.BodyLen,
  o.ViewCount,
  o.Score,
  o.CommentCount,
  o.OwnerBadgeCount,
  o.HistoryEvents,
  o.LastHistoryDate,
  o.TagList,
  o.WeightedScore,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = o.PostId AND v.VoteTypeId = 2) AS Upvotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = o.PostId AND v.VoteTypeId = 3) AS Downvotes
FROM OwnerTop o
LEFT JOIN Users u ON u.Id = o.OwnerUserId
WHERE o.rn = 1

UNION ALL

SELECT
  g.PostId,
  g.Title,
  g.OwnerUserId,
  COALESCE(ug.DisplayName, 'Unknown') AS OwnerDisplayName,
  g.TitleLen,
  g.BodyLen,
  g.ViewCount,
  g.Score,
  g.CommentCount,
  g.OwnerBadgeCount,
  g.HistoryEvents,
  g.LastHistoryDate,
  g.TagList,
  g.WeightedScore,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = g.PostId AND v.VoteTypeId = 2) AS Upvotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = g.PostId AND v.VoteTypeId = 3) AS Downvotes
FROM GlobalTop g
JOIN Users ug ON ug.Id = g.OwnerUserId
WHERE g.rn_all = 1
ORDER BY WeightedScore DESC
LIMIT 100;