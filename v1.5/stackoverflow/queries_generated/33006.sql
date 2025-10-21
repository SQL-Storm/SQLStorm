-- {"query": "33006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 346} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalQuestions,
    COUNT(DISTINCT a.Id) AS TotalAnswers,
    AVG(p.Score) AS AvgQuestionScore,
    AVG(a.Score) AS AvgAnswerScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    COUNT(DISTINCT b.Id) AS BadgesEarned,
    COUNT(DISTINCT c.Id) AS CommentsMade,
    MAX(p.CreationDate) AS LastQuestionDate,
    MAX(a.CreationDate) AS LastAnswerDate,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '1 year') AS QuestionsLastYear,
    COUNT(DISTINCT a.Id) FILTER (WHERE a.CreationDate >= CURRENT_DATE - INTERVAL '1 year') AS AnswersLastYear
FROM
    Users u
LEFT JOIN
    Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN
    Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
LEFT JOIN
    Votes v ON v.UserId = u.Id
LEFT JOIN
    Badges b ON b.UserId = u.Id
LEFT JOIN
    Comments c ON c.UserId = u.Id
GROUP BY
    u.Id, u.DisplayName
ORDER BY
    TotalQuestions DESC, TotalAnswers DESC
LIMIT 100;