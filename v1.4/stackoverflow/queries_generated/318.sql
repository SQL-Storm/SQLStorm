-- {"query": "318.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 23134} 
WITH
user_post_stats AS (
  SELECT
    OwnerUserId AS UserId,
    COUNT(*) AS PostCount,
    COALESCE(SUM(Score), 0) AS TotalScore,
    COALESCE(SUM(ViewCount), 0) AS TotalViews,
    MAX(LastActivityDate) AS LastActivityDate,
    COALESCE(SUM(
      CASE
        WHEN PostTypeId = 1 THEN COALESCE(array_length(string_to_array(substring(Tags, 2, length(Tags) - 2), '><'), 1), 0)
        ELSE 0
      END
    ), 0) AS TotalTagCount
  FROM Posts
  GROUP BY OwnerUserId
),
user_votes AS (
  SELECT UserId,
         COUNT(*) AS VotesCast,
         SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast
  FROM Votes
  GROUP BY UserId
),
user_badges AS (
  SELECT UserId,
         COUNT(*) AS BadgesCount
  FROM Badges
  GROUP BY UserId
),
recent_activity AS (
  SELECT p.OwnerUserId AS UserId,
         MAX(p.LastActivityDate) AS LastPostActivity
  FROM Posts p
  GROUP BY p.OwnerUserId
),
tag_names AS (
  SELECT u.Id AS UserId,
         COALESCE((
           SELECT string_agg(Name, ',')
           FROM (
             SELECT DISTINCT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Name
             FROM Posts p
             WHERE p.OwnerUserId = u.Id AND p.Tags IS NOT NULL
           ) t(Name)
           LIMIT 3
         ), '') AS Top3Tags
  FROM Users u
),
cte_base AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(up.PostCount, 0) AS PostCount,
    COALESCE(up.TotalScore, 0) AS TotalScore,
    COALESCE(up.TotalViews, 0) AS TotalViews,
    COALESCE(ra.LastPostActivity, u.CreationDate) AS LastActivityDate,
    COALESCE(vt.VotesCast, 0) AS VotesCast,
    COALESCE(vt.UpvotesCast, 0) AS UpvotesCast,
    COALESCE(bb.BadgesCount, 0) AS BadgesCount,
    COALESCE(up.TotalTagCount, 0) AS TotalTagCount,
    tg.Top3Tags,
    (
      SELECT Title
      FROM Posts p
      WHERE p.OwnerUserId = u.Id
      ORDER BY p.Score DESC
      LIMIT 1
    ) AS TopPostTitle,
    (
      SELECT COUNT(*)
      FROM Votes w
      WHERE w.UserId = u.Id
        AND w.CreationDate > COALESCE(ra.LastPostActivity, u.CreationDate)
    ) AS VotesSinceLastActivity
  FROM Users u
  LEFT JOIN user_post_stats up ON up.UserId = u.Id
  LEFT JOIN recent_activity ra ON ra.UserId = u.Id
  LEFT JOIN user_votes vt ON vt.UserId = u.Id
  LEFT JOIN user_badges bb ON bb.UserId = u.Id
  LEFT JOIN tag_names tg ON tg.UserId = u.Id
),
base AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      ORDER BY (COALESCE(TotalScore,0) + COALESCE(TotalViews,0) * 0.01 + COALESCE(VotesCast,0) * 0.5 + COALESCE(BadgesCount,0) * 2)
    ) AS RankScoped
  FROM cte_base
),
top_set AS (
  SELECT * FROM base ORDER BY RankScoped DESC LIMIT 100
),
bottom_set AS (
  SELECT * FROM base ORDER BY RankScoped ASC LIMIT 100
)
SELECT *
FROM top_set
UNION ALL
SELECT *
FROM bottom_set
ORDER BY RankScoped;