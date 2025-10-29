-- {"query": "5943.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 768}
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY
),
user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.ProfileImageUrl,
    COALESCE(b.TotalBadges, 0) AS TotalBadges
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON u.Id = b.UserId
),
question_stats AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.ViewCount,
    rq.Score,
    rq.OwnerUserId,
    rq.LastActivityDate,
    rq.CommentCount,
    ua.UserName,
    ua.Reputation,
    ua.TotalBadges,
    AVG(rq.Score) OVER (PARTITION BY rq.OwnerUserId) AS AvgOwnerQuestionScore,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = rq.PostId AND a.PostTypeId = 2) AS AnswerCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rq.PostId) AS LinkedCount,
    CASE WHEN rq.Score = 0 THEN NULL ELSE (CAST(rq.ViewCount AS DOUBLE PRECISION) / CAST(rq.Score AS DOUBLE PRECISION)) END AS ViewPerScore
  FROM recent_questions rq
  LEFT JOIN user_activity ua ON rq.OwnerUserId = ua.UserId
  WHERE rq.rn = 1
),
complex_filter AS (
  SELECT
    qs.PostId,
    qs.Title,
    qs.Tags,
    qs.CreationDate,
    qs.ViewCount,
    qs.Score,
    qs.OwnerUserId,
    qs.LastActivityDate,
    qs.CommentCount,
    qs.UserName,
    qs.Reputation,
    qs.TotalBadges,
    qs.AvgOwnerQuestionScore,
    qs.AnswerCount,
    qs.LinkedCount,
    qs.ViewPerScore,
    CASE
      WHEN qs.ViewCount > 1000 AND qs.Score > 5 THEN TRUE
      WHEN qs.AvgOwnerQuestionScore > 4.0 AND qs.TotalBadges > 2 THEN TRUE
      ELSE FALSE
    END AS HighEngagement
  FROM question_stats qs
),
final_result AS (
  SELECT
    cf.PostId,
    cf.Title,
    cf.Tags,
    cf.CreationDate,
    cf.ViewCount,
    cf.Score,
    cf.OwnerUserId,
    cf.LastActivityDate,
    cf.CommentCount,
    cf.UserName,
    cf.Reputation,
    cf.TotalBadges,
    cf.AvgOwnerQuestionScore,
    cf.AnswerCount,
    cf.LinkedCount,
    cf.ViewPerScore,
    cf.HighEngagement,
    (COALESCE(cf.Score, 0) * 2 + COALESCE(cf.ViewCount, 0) / 10 + COALESCE(cf.AnswerCount, 0)) AS ActivityScore
  FROM complex_filter cf
)
SELECT *
FROM final_result
ORDER BY ActivityScore DESC
LIMIT 100;