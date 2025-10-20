-- {"query": "35065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 862} 
WITH
UserQuestions AS (
  SELECT
    u.Id AS UserId,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    AVG(p.Score) AS AvgQuestionScore
  FROM
    Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  GROUP BY u.Id
),
UserAnswers AS (
  SELECT
    u.Id AS UserId,
    COUNT(DISTINCT p.Id) AS AnswerCount,
    AVG(p.Score) AS AvgAnswerScore
  FROM
    Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
  GROUP BY u.Id
),
UserBadges AS (
  SELECT
    b.UserId,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
  FROM Badges b
  GROUP BY b.UserId
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS UsageCount
  FROM Tags t
  GROUP BY t.TagName
  ORDER BY SUM(t.Count) DESC
  LIMIT 10
),
TagQuestionStats AS (
  SELECT
    regexp_split_to_table(substring(p.Tags, 2, length(p.Tags)-2), '><') AS TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
  GROUP BY TagName
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  uq.QuestionCount,
  uq.AvgQuestionScore,
  ua.AnswerCount,
  ua.AvgAnswerScore,
  ub.GoldBadges,
  ub.SilverBadges,
  ub.BronzeBadges,
  COUNT(DISTINCT c.Id) AS CommentCount,
  (
    SELECT COUNT(1)
    FROM Votes v
    WHERE v.UserId = u.Id
      AND v.VoteTypeId = 2
  ) AS TotalUpvotesGiven,
  (
    SELECT COUNT(1)
    FROM Votes v
    WHERE v.UserId = u.Id
      AND v.VoteTypeId = 3
  ) AS TotalDownvotesGiven,
  (
    SELECT array_agg(tt.TagName)
    FROM TopTags tt
    WHERE tt.TagName IN (
      SELECT DISTINCT regexp_split_to_table(substring(p.Tags, 2, length(p.Tags)-2), '><')
      FROM Posts p
      WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
    )
  ) AS Top10TagsUsedInQuestions,
  (
    SELECT json_agg(json_build_object('TagName', tqs.TagName, 'QuestionCount', tqs.QuestionCount, 'AvgScore', tqs.AvgScore))
    FROM TagQuestionStats tqs
    WHERE tqs.TagName IN (
      SELECT DISTINCT regexp_split_to_table(substring(p.Tags, 2, length(p.Tags)-2), '><')
      FROM Posts p
      WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
    )
  ) AS TagStats
FROM
  Users u
  LEFT JOIN UserQuestions uq ON uq.UserId = u.Id
  LEFT JOIN UserAnswers ua ON ua.UserId = u.Id
  LEFT JOIN UserBadges ub ON ub.UserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
WHERE
  u.Reputation >= 1000
GROUP BY
  u.Id, u.DisplayName, u.Reputation, uq.QuestionCount, uq.AvgQuestionScore, ua.AnswerCount, ua.AvgAnswerScore, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
ORDER BY
  u.Reputation DESC
LIMIT 50;