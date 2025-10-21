-- {"query": "35030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 915} 
WITH HighlyActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT c.Id) AS TotalComments,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate
  FROM
    Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
  WHERE
    u.CreationDate >= NOW() - INTERVAL '3 years'
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.CreationDate
  HAVING
    COUNT(DISTINCT p.Id) + COUNT(DISTINCT c.Id) > 500
),
UserBadges AS (
  SELECT
    b.UserId,
    COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    COUNT(*) AS TotalBadges
  FROM
    Badges b
  GROUP BY
    b.UserId
),
UserVotes AS (
  SELECT
    v.UserId,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesGiven,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS FavoritesGiven
  FROM
    Votes v
  WHERE
    v.UserId IS NOT NULL
  GROUP BY
    v.UserId
),
QuestionAnswerMetrics AS (
  SELECT
    u.Id AS UserId,
    AVG(qa.AnswerCount) AS AvgAnswersPerQuestion,
    AVG(qa.ViewCount) AS AvgViewsPerQuestion
  FROM
    Users u
    JOIN Posts qa ON qa.OwnerUserId = u.Id AND qa.PostTypeId = 1
  GROUP BY
    u.Id
),
TopQuestions AS (
  SELECT
    p.OwnerUserId AS UserId,
    MAX(p.Score) AS TopQuestionScore,
    MAX(p.ViewCount) AS TopQuestionViews
  FROM
    Posts p
  WHERE
    p.PostTypeId = 1
  GROUP BY
    p.OwnerUserId
)
SELECT
  hau.UserId,
  hau.DisplayName,
  hau.TotalPosts,
  hau.TotalComments,
  hau.QuestionsAsked,
  hau.AnswersGiven,
  hau.Reputation,
  hau.UpVotes,
  hau.DownVotes,
  hau.CreationDate,
  COALESCE(ub.GoldBadges, 0) AS GoldBadges,
  COALESCE(ub.SilverBadges, 0) AS SilverBadges,
  COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
  COALESCE(ub.TotalBadges, 0) AS TotalBadges,
  COALESCE(uv.UpvotesGiven, 0) AS UpvotesGiven,
  COALESCE(uv.DownvotesGiven, 0) AS DownvotesGiven,
  COALESCE(uv.FavoritesGiven, 0) AS FavoritesGiven,
  COALESCE(qam.AvgAnswersPerQuestion, 0) AS AvgAnswersPerQuestion,
  COALESCE(qam.AvgViewsPerQuestion, 0) AS AvgViewsPerQuestion,
  COALESCE(tq.TopQuestionScore, 0) AS TopQuestionScore,
  COALESCE(tq.TopQuestionViews, 0) AS TopQuestionViews
FROM
  HighlyActiveUsers hau
  LEFT JOIN UserBadges ub ON hau.UserId = ub.UserId
  LEFT JOIN UserVotes uv ON hau.UserId = uv.UserId
  LEFT JOIN QuestionAnswerMetrics qam ON hau.UserId = qam.UserId
  LEFT JOIN TopQuestions tq ON hau.UserId = tq.UserId
ORDER BY
  hau.TotalPosts + hau.TotalComments DESC, hau.Reputation DESC
LIMIT 50;