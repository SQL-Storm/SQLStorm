-- {"query": "39086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 3322} 
WITH RECURSIVE MonthBounds AS (
  SELECT
    date_trunc('month', MIN(CreationDate)) AS start_month,
    date_trunc('month', MAX(CreationDate)) AS end_month
  FROM Posts
),
Months AS (
  SELECT start_month AS month_start
  FROM MonthBounds
  UNION ALL
  SELECT month_start + INTERVAL '1 month'
  FROM Months, MonthBounds
  WHERE month_start + INTERVAL '1 month' <= MonthBounds.end_month
),
QuestionTagPairs AS (
  SELECT
    p.Id           AS PostId,
    date_trunc('month', p.CreationDate) AS month,
    unnest(
      string_to_array(
        substring(p.Tags, 2, length(p.Tags) - 2),
        '><'
      )
    ) AS tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
MonthlyTagStats AS (
  SELECT
    m.month_start         AS month,
    qtp.tag,
    COUNT(*)              AS question_count,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS avg_score,
    ROW_NUMBER() OVER (PARTITION BY m.month_start ORDER BY COUNT(*) DESC) AS rank_by_count
  FROM Months m
  LEFT JOIN QuestionTagPairs qtp
    ON qtp.month = m.month_start
  LEFT JOIN Posts p
    ON p.Id = qtp.PostId
  GROUP BY m.month_start, qtp.tag
),
TopTagsPerMonth AS (
  SELECT month, tag
  FROM MonthlyTagStats
  WHERE rank_by_count <= 5
),
UserPostStats AS (
  SELECT
    u.Id              AS user_id,
    u.DisplayName,
    COUNT(p.Id)       AS total_posts,
    COALESCE(SUM(p.Score), 0) AS total_score
  FROM Users u
  LEFT JOIN Posts p
    ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
BadgeBreakdown AS (
  SELECT
    b.UserId AS user_id,
    SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold,
    SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver,
    SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS bronze
  FROM Badges b
  GROUP BY b.UserId
),
UserTagActivities AS (
  SELECT
    p.OwnerUserId AS user_id,
    qtp.tag,
    qtp.month
  FROM Posts p
  JOIN QuestionTagPairs qtp
    ON qtp.PostId = p.Id
  WHERE date_trunc('month', p.CreationDate) >= date_trunc('month', cast('2024-10-01' as date)) - INTERVAL '5 months'
),
UserTopTagInteractions AS (
  SELECT
    uta.user_id,
    uta.tag,
    COUNT(*) AS interactions
  FROM UserTagActivities uta
  GROUP BY uta.user_id, uta.tag
),
UserTrendingTags AS (
  SELECT
    utt.user_id,
    array_agg(utt.tag ORDER BY utt.interactions DESC, utt.tag) AS trending_tags
  FROM UserTopTagInteractions utt
  GROUP BY utt.user_id
)
SELECT
  ups.user_id,
  ups.DisplayName,
  ups.total_posts,
  ups.total_score,
  COALESCE(bb.gold, 0)   AS gold,
  COALESCE(bb.silver, 0) AS silver,
  COALESCE(bb.bronze, 0) AS bronze,
  utt.trending_tags
FROM UserPostStats ups
LEFT JOIN BadgeBreakdown bb
  ON bb.user_id = ups.user_id
LEFT JOIN UserTrendingTags utt
  ON utt.user_id = ups.user_id
ORDER BY ups.total_score DESC NULLS LAST, ups.total_posts DESC
LIMIT 50;