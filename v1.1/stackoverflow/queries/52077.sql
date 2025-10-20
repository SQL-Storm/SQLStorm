-- {"query": "52077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 662} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        AVG(ph.RevisionCount) AS AvgEditsPerPost
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN (
        SELECT 
            PostId,
            COUNT(*) AS RevisionCount
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4,5,6) -- Edit types
        GROUP BY PostId
    ) ph ON p.Id = ph.PostId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeScores AS (
    SELECT 
        UserId,
        SUM(CASE WHEN Class = 1 THEN 100 WHEN Class = 2 THEN 10 ELSE 1 END) AS BadgeScore
    FROM Badges
    GROUP BY UserId
),
InfluenceScore AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.TotalPosts,
        us.QuestionsAsked,
        us.AnswersGiven,
        us.TotalScore,
        us.TotalViews,
        us.TotalComments,
        us.TotalVotes,
        us.TotalBadges,
        us.AvgEditsPerPost,
        COALESCE(bs.BadgeScore, 0) AS BadgeScore,
        (us.TotalScore * 1.0 / NULLIF(us.TotalPosts, 0)) AS AvgPostScore,
        (us.AnswersGiven * 1.0 / NULLIF(us.QuestionsAsked, 0)) AS AnswerToQuestionRatio,
        RANK() OVER (ORDER BY us.Reputation + COALESCE(bs.BadgeScore, 0) + us.TotalScore DESC) AS RankByInfluence
    FROM UserStats us
    LEFT JOIN BadgeScores bs ON us.UserId = bs.UserId
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    TotalPosts,
    QuestionsAsked,
    AnswersGiven,
    TotalScore,
    TotalViews,
    TotalComments,
    TotalVotes,
    TotalBadges,
    ROUND(AvgEditsPerPost, 2) AS AvgEditsPerPost,
    BadgeScore,
    ROUND(AvgPostScore, 2) AS AvgPostScore,
    ROUND(AnswerToQuestionRatio, 2) AS AnswerToQuestionRatio,
    RankByInfluence
FROM InfluenceScore
ORDER BY RankByInfluence
LIMIT 100;