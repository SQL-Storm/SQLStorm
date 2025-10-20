-- {"query": "52002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 687} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        SUM(v.UpVotes + v.DownVotes) AS TotalVotesReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
                      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY PostId
    ) v ON p.Id = v.PostId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeStats AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
CommentStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(c.Id) AS TotalCommentsReceived
    FROM Posts p
    JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.OwnerUserId
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalPosts,
    us.TotalAnswers,
    us.TotalQuestions,
    us.TotalQuestionScore,
    us.TotalAnswerScore,
    us.AvgQuestionScore,
    us.AvgAnswerScore,
    us.TotalVotesReceived,
    COALESCE(bs.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(cs.TotalCommentsReceived, 0) AS TotalCommentsReceived,
    ROW_NUMBER() OVER (ORDER BY us.TotalVotesReceived DESC, us.Reputation DESC) AS RankByVotes,
    DENSE_RANK() OVER (ORDER BY COALESCE(bs.GoldBadges, 0) DESC, us.Reputation DESC) AS RankByGoldBadges
FROM UserStats us
LEFT JOIN BadgeStats bs ON us.UserId = bs.UserId
LEFT JOIN CommentStats cs ON us.UserId = cs.UserId
WHERE us.TotalPosts > 10
ORDER BY us.TotalVotesReceived DESC, us.Reputation DESC
LIMIT 100;