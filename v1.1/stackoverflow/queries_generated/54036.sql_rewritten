-- {"query": "54036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1921} 
WITH user_posts AS (
  SELECT 
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate,
    u.DisplayName,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS Questions,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS Answers,
    SUM(p.Score) AS TotalScore,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName
),
user_votes AS (
  SELECT 
    u.Id AS UserId,
    COUNT(v.Id) AS TotalVotes,
    SUM(v.BountyAmount) AS BountySum,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id
),
user_badges AS (
  SELECT 
    u.Id AS UserId,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    COUNT(*) AS TotalBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id
)
SELECT 
  up.UserId,
  up.Reputation,
  up.CreationDate,
  up.DisplayName,
  up.Questions,
  up.Answers,
  up.TotalScore,
  up.AvgQuestionScore,
  up.AvgAnswerScore,
  uv.TotalVotes,
  uv.BountySum,
  uv.UpVotes,
  uv.DownVotes,
  ub.GoldBadges,
  ub.SilverBadges,
  ub.BronzeBadges,
  ub.TotalBadges,
  (SELECT COUNT(*) FROM Comments c WHERE c.UserId = up.UserId) AS CommentCount,
  (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = up.UserId AND ph.PostHistoryTypeId = 5) AS BodyEdits,
  (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.UserId = up.UserId) AS LastEdit
FROM user_posts up
LEFT JOIN user_votes uv ON uv.UserId = up.UserId
LEFT JOIN user_badges ub ON ub.UserId = up.UserId
ORDER BY up.TotalScore DESC
LIMIT 1000;