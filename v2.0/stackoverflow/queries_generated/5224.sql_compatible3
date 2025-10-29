WITH TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.PostTypeId,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2' YEAR)
),
OwnerStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(t.PostId) AS TopQuestionCount,
    SUM(t.Score) AS TotalScoreFromTopQuestions,
    SUM(CASE WHEN t.ViewCount IS NOT NULL THEN t.ViewCount ELSE 0 END) AS TotalViewsFromTopQuestions
  FROM TopPosts t
  JOIN Users u ON u.Id = t.OwnerUserId
  WHERE t.rn_owner = 1
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
Agg AS (
  SELECT
    o.UserId,
    o.DisplayName,
    o.Reputation,
    o.TopQuestionCount,
    o.TotalScoreFromTopQuestions,
    o.TotalViewsFromTopQuestions,
    (
      SELECT AVG(CASE WHEN c.tag_present THEN 1.0 ELSE 0.0 END)
      FROM (
        SELECT
          CASE
            WHEN (ARRAY_LENGTH(string_to_array(REPLACE(t.Tags, '<', ''), '><'), 1) IS NOT NULL
                  AND ARRAY_LENGTH(string_to_array(REPLACE(t.Tags, '<', ''), '><'), 1) > 0)
                 THEN true
                 ELSE false
          END AS tag_present
        FROM TopPosts t
        WHERE t.OwnerUserId = o.UserId AND t.rn_owner = 1
      ) c
    ) AS TopTagsPresenceRatio,
    NTILE(4) OVER (ORDER BY o.TotalScoreFromTopQuestions DESC) AS ScoreQuartile
  FROM OwnerStats o
)
SELECT
  a.UserId,
  a.DisplayName,
  a.Reputation,
  a.TopQuestionCount,
  a.TotalScoreFromTopQuestions,
  a.TotalViewsFromTopQuestions,
  a.TopTagsPresenceRatio,
  a.ScoreQuartile,
  (
    SELECT AVG(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate)) / 86400.0)
    FROM TopPosts p
    WHERE p.OwnerUserId = a.UserId
  ) AS AvgAgeDaysTopQuestions,
  COALESCE((
    SELECT SUM(c.cnt)
    FROM (
      SELECT COUNT(*) AS cnt
      FROM Comments cm
      WHERE cm.PostId IN (
        SELECT PostId FROM TopPosts WHERE OwnerUserId = a.UserId AND rn_owner = 1
      )
    ) c
  ), 0) AS TotalCommentsOnTopQuestion
FROM Agg a
ORDER BY a.TotalScoreFromTopQuestions DESC
LIMIT 100;