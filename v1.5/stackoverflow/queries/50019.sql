-- {"query": "50019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 977} 
WITH UserBadges AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserContentStats AS (
    SELECT
        p.OwnerUserId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.FavoriteCount ELSE 0 END) AS TotalFavorites
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserEngagement AS (
    SELECT
        c.UserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesGiven
    FROM Comments c
    JOIN Votes v ON c.UserId = v.UserId
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
AcceptedAnswerRatio AS (
    SELECT
        p_ans.OwnerUserId,
        COUNT(*) AS TotalAnswers,
        CAST(SUM(CASE WHEN p_que.AcceptedAnswerId = p_ans.Id THEN 1 ELSE 0 END) AS decimal) / COUNT(*) AS AcceptanceRatio
    FROM Posts p_ans
    JOIN Posts p_que ON p_ans.ParentId = p_que.Id
    WHERE p_ans.PostTypeId = 2 AND p_ans.OwnerUserId IS NOT NULL
    GROUP BY p_ans.OwnerUserId
    HAVING COUNT(*) > 10
)
SELECT
    u.DisplayName,
    u.Reputation,
    u.Location,
    ucs.QuestionCount,
    ucs.AnswerCount,
    aar.AcceptanceRatio,
    ub.GoldBadges,
    ub.SilverBadges,
    ue.CommentCount,
    ue.UpvotesGiven,
    (
        (u.Reputation * 0.4) +
        (ucs.TotalAnswerScore * 0.25) +
        (ucs.TotalQuestionScore * 0.1) +
        (COALESCE(aar.AcceptanceRatio, 0) * 500) +
        (ub.GoldBadges * 100) +
        (ub.SilverBadges * 25) +
        (ue.TotalCommentScore * 0.15) +
        (ucs.TotalFavorites * 2)
    ) AS OverallScore,
    DENSE_RANK() OVER (PARTITION BY SUBSTRING(u.Location, POSITION(',' IN u.Location) + 1) ORDER BY u.Reputation DESC) AS LocationReputationRank
FROM Users u
JOIN UserContentStats ucs ON u.Id = ucs.OwnerUserId
JOIN UserBadges ub ON u.Id = ub.UserId
LEFT JOIN UserEngagement ue ON u.Id = ue.UserId
LEFT JOIN AcceptedAnswerRatio aar ON u.Id = aar.OwnerUserId
WHERE
    u.CreationDate BETWEEN '2015-01-01' AND '2020-12-31'
    AND u.Reputation > (SELECT AVG(Reputation) FROM Users)
    AND ucs.AnswerCount > ucs.QuestionCount
    AND ub.GoldBadges > 0
    AND u.Location LIKE '%, %'
ORDER BY
    OverallScore DESC, u.Reputation DESC
LIMIT 250;