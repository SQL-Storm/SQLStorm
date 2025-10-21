-- {"query": "33051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 497} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalQuestions,
    COUNT(DISTINCT a.Id) AS TotalAnswers,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    AVG(a.Score) FILTER (WHERE a.PostTypeId = 2) AS AvgAnswerScore,
    SUM(p.ViewCount) AS TotalQuestionViews,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT b.Id) AS BadgesEarned,
    MAX(p.CreationDate) AS LastQuestionDate,
    COUNT(DISTINCT v_up.Id) AS UpvoteCount,
    COUNT(DISTINCT v_down.Id) AS DownvoteCount,
    SUM(CASE WHEN v.typeid = 5 THEN 1 ELSE 0 END) AS TotalFavorites,
    (
        SELECT COUNT(*) FROM Posts p2
        WHERE p2.OwnerUserId = u.Id
        AND p2.PostTypeId IN (1, 2)
        AND p2.CreationDate >= NOW() - INTERVAL '1 year'
    ) AS QuestionsPastYear,
    (
        SELECT COUNT(*) FROM Posts p3
        WHERE p3.OwnerUserId = u.Id
        AND p3.PostTypeId = 2
        AND p3.Score >= 10
    ) AS HighScoreAnswers,
    EXISTS (
        SELECT 1 FROM Badges b2 WHERE b2.UserId = u.Id AND b2.Name ILIKE '%gold%'
    ) AS HasGoldBadge
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
LEFT JOIN Comments c ON c.PostId IN (p.Id, a.Id)
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id
LEFT JOIN Votes v_up ON v_up.UserId = u.Id AND v_up.VoteTypeId = 2
LEFT JOIN Votes v_down ON v_down.UserId = u.Id AND v_down.VoteTypeId = 3
WHERE u.CreationDate <= NOW() - INTERVAL '6 months'
GROUP BY u.Id, u.DisplayName
ORDER BY TotalQuestions DESC
LIMIT 100;