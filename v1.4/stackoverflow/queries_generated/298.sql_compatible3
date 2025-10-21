WITH
RecentQuestions AS (
  SELECT p.Id AS PostId, p.Title, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.ViewCount, p.Score, p.Tags
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180' DAY
),
VeryViewed AS (
  SELECT p.Id AS PostId, p.Title, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.ViewCount, p.Score, p.Tags
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ViewCount > 10000
    AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365' DAY
),
PostSet AS (
  SELECT * FROM RecentQuestions
  UNION ALL
  SELECT * FROM VeryViewed
),
VotesSummary AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                  WHEN v.VoteTypeId = 3 THEN -1
                  ELSE 0 END) AS NetVotes
  FROM Votes v
  GROUP BY v.PostId
),
CommentsCount AS (
  SELECT c.PostId, COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
),
Metrics AS (
  SELECT ps.PostId, ps.Title, ps.OwnerUserId, ps.CreationDate, ps.LastActivityDate, ps.ViewCount, ps.Score, ps.Tags,
         COALESCE(vs.NetVotes, 0) AS NetVotes,
         COALESCE(cc.CommentCount, 0) AS CommentCount
  FROM PostSet ps
  LEFT JOIN VotesSummary vs ON vs.PostId = ps.PostId
  LEFT JOIN CommentsCount cc ON cc.PostId = ps.PostId
),
OwnerStats AS (
  SELECT b.UserId, COUNT(*) AS GoldBadges
  FROM Badges b
  WHERE b.Class = 1
  GROUP BY b.UserId
),
Final AS (
  SELECT m.PostId,
         m.Title,
         u.DisplayName AS OwnerName,
         m.CreationDate,
         m.LastActivityDate,
         m.ViewCount,
         m.Score,
         m.NetVotes,
         m.CommentCount,
         CASE
           WHEN m.Tags IS NOT NULL THEN
             ARRAY_TO_STRING(
               COALESCE(string_to_array(substr(m.Tags, 2, LENGTH(m.Tags) - 2), '><'), ARRAY[]::text[]),
               ','
             )
           ELSE NULL
         END AS TagList,
         u.Reputation AS OwnerReputation,
         COALESCE(os.GoldBadges, 0) AS OwnerGoldBadges,
         (
           SELECT c.Text
           FROM Comments c
           WHERE c.PostId = m.PostId
           ORDER BY c.CreationDate DESC
           LIMIT 1
         ) AS LatestComment
  FROM Metrics m
  LEFT JOIN Users u ON u.Id = m.OwnerUserId
  LEFT JOIN OwnerStats os ON os.UserId = m.OwnerUserId
),
Ranked AS (
  SELECT r.*,
         LOG(1 + GREATEST(0, r.ViewCount)) AS LogViews,
         (2.0 * r.NetVotes) + (1.5 * r.CommentCount) + (0.5 * r.Score) + (0.25 * LOG(1 + GREATEST(0, r.ViewCount))) AS EngagementScore
  FROM Final r
)
SELECT PostId, Title, OwnerName, CreationDate, LastActivityDate, ViewCount, Score, NetVotes, CommentCount,
       TagList, OwnerReputation, OwnerGoldBadges, LatestComment, LogViews, EngagementScore
FROM Ranked
ORDER BY EngagementScore DESC
LIMIT 100;