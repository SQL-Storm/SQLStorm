-- {"query": "50090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1119} 
WITH UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    MIN(p.CreationDate) AS FirstPostDate,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 0) AS TotalAnswerScore,
    COALESCE(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 0) AS AverageAnswerScore,
    COUNT(DISTINCT CASE WHEN p.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 year') THEN p.Id END) AS RecentPostCount
  FROM Users AS u
  LEFT JOIN Posts AS p
    ON u.Id = p.OwnerUserId
  WHERE u.Reputation > 1000 AND p.OwnerUserId IS NOT NULL
  GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate
), BadgeCounts AS (
  SELECT
    b.UserId,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
  FROM Badges AS b
  GROUP BY
    b.UserId
), UserEngagement AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(DISTINCT v.Id) AS UpvotesReceived,
    COUNT(DISTINCT c.Id) AS CommentsMade,
    COUNT(DISTINCT CASE WHEN c.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 year') THEN c.Id END) AS RecentCommentCount
  FROM Posts AS p
  LEFT JOIN Votes AS v
    ON p.Id = v.PostId AND v.VoteTypeId = 2
  LEFT JOIN Comments AS c
    ON p.OwnerUserId = c.UserId
  WHERE
    p.OwnerUserId IS NOT NULL
  GROUP BY
    p.OwnerUserId
), RankedUsers AS (
  SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    (
      (ua.Reputation * 0.1) + (ua.TotalAnswerScore * 0.4) + (COALESCE(bc.GoldBadges, 0) * 1000) + (COALESCE(bc.SilverBadges, 0) * 100) + (COALESCE(ue.UpvotesReceived, 0) * 0.2) + ((ua.RecentPostCount + COALESCE(ue.RecentCommentCount, 0)) * 25)
    ) AS PowerScore,
    ua.UserCreationDate,
    ua.FirstPostDate,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.AverageAnswerScore,
    COALESCE(bc.GoldBadges, 0) AS GoldBadges,
    COALESCE(bc.SilverBadges, 0) AS SilverBadges,
    COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ue.UpvotesReceived, 0) AS UpvotesReceived,
    COALESCE(ue.CommentsMade, 0) AS CommentsMade
  FROM UserActivity AS ua
  JOIN BadgeCounts AS bc
    ON ua.UserId = bc.UserId
  JOIN UserEngagement AS ue
    ON ua.UserId = ue.UserId
  WHERE
    bc.GoldBadges > 0 AND ua.AnswerCount > 10
)
SELECT
  DENSE_RANK() OVER (ORDER BY ru.PowerScore DESC) AS UserRank,
  ru.DisplayName,
  ru.Reputation,
  ru.PowerScore,
  ru.QuestionCount,
  ru.AnswerCount,
  CAST(ru.AverageAnswerScore AS DECIMAL(10, 2)) AS AverageAnswerScore,
  ru.UpvotesReceived,
  ru.CommentsMade,
  ru.GoldBadges,
  ru.SilverBadges,
  ru.BronzeBadges,
  ru.UserCreationDate,
  (
    SELECT
      q.Title
    FROM Posts AS p
    JOIN Posts AS q
      ON p.ParentId = q.Id
    WHERE
      p.OwnerUserId = ru.UserId AND p.PostTypeId = 2
    ORDER BY
      p.Score DESC,
      p.CreationDate DESC
    LIMIT 1
  ) AS TopAnswerOnQuestion
FROM RankedUsers AS ru
ORDER BY
  UserRank,
  ru.Reputation DESC
LIMIT 100;