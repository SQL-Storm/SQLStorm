-- {"query": "35044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 788} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        MAX(u.Reputation) AS MaxReputation,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(p.ViewCount) AS TotalPostViews,
        SUM(p.Score) AS TotalPostScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
RecentTopUsers AS (
    SELECT 
        UserId, 
        DisplayName,
        TotalPosts, 
        TotalComments, 
        TotalVotes, 
        MaxReputation,
        TotalQuestions,
        TotalAnswers,
        TotalPostViews,
        TotalPostScore,
        RANK() OVER (ORDER BY MaxReputation DESC, TotalPostScore DESC) AS ReputationRank
    FROM UserActivityStats 
    WHERE TotalPosts > 15 AND MaxReputation > 1000
    LIMIT 50
),
HotQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COUNT(a.Id) AS AnswerCount,
        SUM(a.Score) AS TotalAnswerScore
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1 
        AND p.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount
    HAVING COUNT(a.Id) > 1
),
BadgeStats AS (
    SELECT 
        u.Id AS UserId, 
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.ReputationRank,
    ru.TotalPosts,
    ru.TotalQuestions,
    ru.TotalAnswers,
    ru.TotalComments,
    ru.TotalVotes,
    ru.TotalPostViews,
    ru.TotalPostScore,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    hq.QuestionId AS RecentHotQuestionId,
    hq.Title AS RecentHotQuestionTitle,
    hq.CreationDate AS RecentHotQuestionDate,
    hq.Score AS RecentHotQuestionScore,
    hq.ViewCount AS RecentHotQuestionViews,
    hq.AnswerCount AS RecentHotQuestionAnswerCount,
    hq.TotalAnswerScore AS RecentHotQuestionAnswerScore 
FROM RecentTopUsers ru
LEFT JOIN BadgeStats bs ON bs.UserId = ru.UserId
LEFT JOIN HotQuestions hq ON hq.OwnerUserId = ru.UserId
ORDER BY ru.ReputationRank, hq.Score DESC NULLS LAST, hq.CreationDate DESC NULLS LAST
LIMIT 100;