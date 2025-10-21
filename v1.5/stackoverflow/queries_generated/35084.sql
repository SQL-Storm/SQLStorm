-- {"query": "35084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 730} 
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        SUM(p.Score) AS TotalPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopPosters AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        Questions,
        Answers,
        TotalPosts,
        TotalPostScore,
        TotalViews,
        TotalComments,
        TotalBadges,
        LastPostDate,
        RANK() OVER (ORDER BY TotalPosts DESC, Reputation DESC) AS PostRank
    FROM UserActivity
    WHERE TotalPosts > 0
    LIMIT 1000
),
QuestionAnswerStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        MAX(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS MaxAnswerScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS SumAnswerScore
    FROM Posts p
    GROUP BY p.OwnerUserId
)
SELECT
    t.PostRank,
    t.UserId,
    t.DisplayName,
    t.Reputation,
    t.Questions,
    t.Answers,
    t.TotalPosts,
    t.TotalPostScore,
    t.TotalViews,
    t.TotalComments,
    t.TotalBadges,
    t.LastPostDate,
    COALESCE(qas.AvgQuestionScore, 0) AS AvgQuestionScore,
    COALESCE(qas.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(qas.MaxAnswerScore, 0) AS MaxAnswerScore,
    COALESCE(qas.SumAnswerScore, 0) AS SumAnswerScore,
    b2.BadgeCount_Gold,
    b2.BadgeCount_Silver,
    b2.BadgeCount_Bronze
FROM TopPosters t
LEFT JOIN QuestionAnswerStats qas ON qas.UserId = t.UserId
LEFT JOIN (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS BadgeCount_Gold,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS BadgeCount_Silver,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BadgeCount_Bronze
    FROM Badges
    GROUP BY UserId
) b2 ON b2.UserId = t.UserId
ORDER BY t.PostRank
LIMIT 100;