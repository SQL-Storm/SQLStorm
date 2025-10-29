WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.PostTypeId,
    p.Body
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
),
expanded_tags AS (
  SELECT
    rq.*,
    unnest(string_to_array(substr(rq.Tags, 2, length(rq.Tags) - 2), '><')) AS TagName
  FROM recent_questions rq
),
tag_stats AS (
  SELECT
    TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews,
    SUM(p.AnswerCount) AS TotalAnswers
  FROM expanded_tags et
  JOIN Posts p ON p.Id = et.PostId
  GROUP BY TagName
),
dynamic_filters AS (
  SELECT
    et.*,
    CASE
      WHEN et.Score >= 10 THEN 'HighScore'
      WHEN et.ViewCount >= 1000 THEN 'Popular'
      ELSE 'NewOrMedium'
    END AS Momentum
  FROM expanded_tags et
),
windows AS (
  SELECT
    dt.PostId,
    dt.Title,
    dt.CreationDate,
    dt.Score,
    dt.ViewCount,
    dt.Tags,
    dt.OwnerUserId,
    dt.OwnerDisplayName,
    dt.LastActivityDate,
    dt.CommentCount,
    dt.AnswerCount,
    dt.FavoriteCount,
    dt.PostTypeId,
    dt.Body,
    dt.Momentum,
    ROW_NUMBER() OVER (PARTITION BY dt.OwnerUserId ORDER BY dt.CreationDate DESC) AS rn_by_user,
    RANK() OVER (ORDER BY dt.LastActivityDate DESC) AS latest_rank
  FROM dynamic_filters dt
),
aggregates AS (
  SELECT
    w.OwnerUserId,
    MIN(w.CreationDate) AS FirstQuestionDate,
    MAX(w.LastActivityDate) AS LastActiveQuestion,
    AVG(w.Score) AS AvgScorePerUser,
    SUM(w.ViewCount) AS TotalViewsByUser
  FROM windows w
  GROUP BY w.OwnerUserId
),
correlated AS (
  SELECT
    w.PostId,
    w.Title,
    w.CreationDate,
    w.Score,
    w.ViewCount,
    w.Tags,
    w.OwnerUserId,
    w.OwnerDisplayName,
    w.LastActivityDate,
    w.CommentCount,
    w.AnswerCount,
    w.FavoriteCount,
    w.PostTypeId,
    w.Body,
    w.Momentum,
    w.rn_by_user,
    w.latest_rank,
    a.FirstQuestionDate,
    a.LastActiveQuestion,
    a.AvgScorePerUser,
    a.TotalViewsByUser,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = w.OwnerUserId AND b.Class = 1) AS GoldBadges,
    (SELECT COALESCE(SUM(bc.BadgeTotal), 0)
       FROM (
         SELECT COUNT(*) AS BadgeTotal
         FROM Badges b2
         WHERE b2.UserId = w.OwnerUserId
         GROUP BY b2.Name
       ) AS bc
    ) AS TotalBadgesDistinct
  FROM windows w
  LEFT JOIN aggregates a ON a.OwnerUserId = w.OwnerUserId
)
SELECT
  c.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  c.FirstQuestionDate,
  c.LastActiveQuestion,
  c.AvgScorePerUser,
  c.TotalViewsByUser,
  c.GoldBadges,
  c.TotalBadgesDistinct,
  c.Title,
  c.PostId,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.Tags,
  c.Body,
  c.Momentum,
  c.rn_by_user,
  c.latest_rank
FROM correlated c
LEFT JOIN Users u ON u.Id = c.OwnerUserId
WHERE c.latest_rank <= 50
  AND c.Momentum IN ('HighScore', 'Popular')
ORDER BY c.LastActiveQuestion DESC, c.Score DESC
LIMIT 100;