-- {"query": "50028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 938} 

WITH UserActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(p.Score) AS TotalPostScore,
        SUM(p.ViewCount) AS TotalViewCount,
        SUM(p.FavoriteCount) AS TotalFavoriteCount,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.LastActivityDate) AS LastActivityDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate > '2015-01-01'
    GROUP BY p.OwnerUserId
    HAVING COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 10 AND COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 20
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
RankedAnswers AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId,
        p.Score,
        p.Body,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate ASC) as rn
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.OwnerUserId IS NOT NULL
),
UserEngagement AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT v.UserId) AS UniqueVoters,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.CreationDate AS UserCreationDate,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalViewCount,
    ua.TotalFavoriteCount,
    ue.UpvotesReceived,
    ue.DownvotesReceived,
    ub.GoldBadges,
    ub.SilverBadges,
    q.Title AS TopAnswerQuestionTitle,
    ra.Score AS TopAnswerScore,
    (EXTRACT(EPOCH FROM (ua.LastActivityDate - u.CreationDate)) / 86400.0) / (ua.TotalQuestions + ua.TotalAnswers) AS AvgDaysPerPost,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC, ub.GoldBadges DESC) AS OverallRank
FROM Users u
JOIN UserActivity ua ON u.Id = ua.OwnerUserId
JOIN UserBadges ub ON u.Id = ub.UserId
JOIN UserEngagement ue ON u.Id = ue.OwnerUserId
LEFT JOIN RankedAnswers ra ON u.Id = ra.OwnerUserId AND ra.rn = 1
LEFT JOIN Posts q ON ra.QuestionId = q.Id
WHERE u.Reputation > 100000
  AND ub.GoldBadges > 5
  AND u.Location LIKE '%United%'
  AND u.Id IN (
    SELECT c.UserId
    FROM Comments c
    GROUP BY c.UserId
    HAVING COUNT(c.Id) > 500 AND AVG(c.Score) > 2
  )
ORDER BY
    u.Reputation DESC,
    ub.GoldBadges DESC,
    ua.TotalAnswers DESC
LIMIT 100;
