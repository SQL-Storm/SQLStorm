-- {"query": "35001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 809} 
WITH user_activity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        COALESCE(SUM(p.ViewCount),0) AS TotalViews,
        COALESCE(SUM(p.Score),0) AS TotalScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
)
, top_answerers AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) AS AnswerCount,
        SUM(p.Score) AS AnswersTotalScore
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY p.OwnerUserId
    HAVING COUNT(*) > 20
)
, badge_counts AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
, hot_questions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.ViewCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        MAX(p.Score) AS MaxScore
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1 AND p.ViewCount > 1000 AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months'
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.ViewCount
    HAVING COUNT(DISTINCT a.Id) >= 5
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalViews,
    ua.TotalScore,
    bc.TotalBadges,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    ta.AnswerCount AS RecentAnswers,
    ta.AnswersTotalScore AS RecentAnswerScore,
    COUNT(DISTINCT hq.QuestionId) AS HotQuestionsAuthored
FROM user_activity ua
LEFT JOIN badge_counts bc ON bc.UserId = ua.UserId
LEFT JOIN top_answerers ta ON ta.OwnerUserId = ua.UserId
LEFT JOIN hot_questions hq ON hq.OwnerUserId = ua.UserId
WHERE 
    ua.TotalPosts > 10
    AND (ta.AnswerCount > 50 OR ua.TotalScore > 200)
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalViews,
    ua.TotalScore,
    bc.TotalBadges,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    ta.AnswerCount,
    ta.AnswersTotalScore
ORDER BY
    (COALESCE(ta.AnswersTotalScore,0) + ua.TotalScore + COALESCE(bc.GoldBadges,0)*100) DESC
LIMIT 50;