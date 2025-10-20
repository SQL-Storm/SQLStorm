-- {"query": "35099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 796} 
WITH TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS Answers,
    SUM(p.Score) AS TotalPostScore
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  JOIN PostTypes pt ON p.PostTypeId = pt.Id
  WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
  GROUP BY u.Id, u.DisplayName, u.Reputation
  HAVING COUNT(DISTINCT p.Id) >= 50
),
UserBadges AS (
  SELECT
    b.UserId,
    COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    COUNT(*) AS TotalBadges
  FROM Badges b
  WHERE b.Date >= NOW() - INTERVAL '1 year'
  GROUP BY b.UserId
),
UserVotes AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesReceived,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesReceived
  FROM Votes v
  JOIN Posts p ON p.Id = v.PostId
  GROUP BY p.OwnerUserId
),
TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Score,
    p.ViewCount,
    COUNT(c.Id) AS CommentCount
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  WHERE p.PostTypeId = 1 AND p.CreationDate >= NOW() - INTERVAL '1 year'
  GROUP BY p.Id, p.OwnerUserId, p.Title, p.Score, p.ViewCount
  HAVING p.Score >= 10 AND p.ViewCount >= 1000
)
SELECT
  tu.UserId,
  tu.DisplayName,
  tu.Reputation,
  tu.TotalPosts,
  tu.Questions,
  tu.Answers,
  tu.TotalPostScore,
  COALESCE(b.TotalBadges, 0) AS TotalBadges,
  COALESCE(b.GoldBadges, 0) AS GoldBadges,
  COALESCE(b.SilverBadges, 0) AS SilverBadges,
  COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
  COALESCE(v.UpVotesReceived, 0) AS UpVotesReceived,
  COALESCE(v.DownVotesReceived, 0) AS DownVotesReceived,
  COUNT(DISTINCT tq.PostId) AS TopQuestionsLastYear,
  MAX(tq.Score) AS MaxQuestionScore,
  MAX(tq.ViewCount) AS MaxQuestionViews
FROM TopUsers tu
LEFT JOIN UserBadges b ON tu.UserId = b.UserId
LEFT JOIN UserVotes v ON tu.UserId = v.UserId
LEFT JOIN TopQuestions tq ON tq.OwnerUserId = tu.UserId
GROUP BY
  tu.UserId, tu.DisplayName, tu.Reputation,
  tu.TotalPosts, tu.Questions, tu.Answers, tu.TotalPostScore,
  b.TotalBadges, b.GoldBadges, b.SilverBadges, b.BronzeBadges,
  v.UpVotesReceived, v.DownVotesReceived
ORDER BY
  tu.Reputation DESC,
  tu.TotalPostScore DESC
LIMIT 25;