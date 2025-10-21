-- {"query": "33049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 434} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalQuestions,
    COUNT(DISTINCT a.Id) AS TotalAnswers,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    AVG(a.Score) FILTER (WHERE a.PostTypeId = 2) AS AvgAnswerScore,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT v_up.Id) AS UpvotesReceived,
    COUNT(DISTINCT v_down.Id) AS DownvotesReceived,
    COUNT(DISTINCT badges.Id) AS BadgesCount,
    SUM(CASE WHEN p.ViewCount > 1000 THEN 1 ELSE 0 END) AS QuestionsOver1000Views,
    DATE_TRUNC('month', u.CreationDate) AS SignupMonth
FROM
    Users u
LEFT JOIN
    Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN
    Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
LEFT JOIN
    Comments c ON c.UserId = u.Id
LEFT JOIN
    Votes v_up ON v_up.UserId = u.Id AND v_up.VoteTypeId = 2
LEFT JOIN
    Votes v_down ON v_down.UserId = u.Id AND v_down.VoteTypeId = 3
LEFT JOIN
    Badges badges ON badges.UserId = u.Id
LEFT JOIN
    Votes v_up_received ON v_up_received.PostId = p.Id AND v_up_received.VoteTypeId = 2
LEFT JOIN
    Votes v_down_received ON v_down_received.PostId = p.Id AND v_down_received.VoteTypeId = 3
WHERE
    u.CreationDate >= DATE '2010-01-01'
    AND u.LastAccessDate <= NOW()
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    SignupMonth
ORDER BY
    u.Reputation DESC
LIMIT 100;