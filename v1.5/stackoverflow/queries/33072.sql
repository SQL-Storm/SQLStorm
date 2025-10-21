-- {"query": "33072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 320} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalQuestions,
    COUNT(DISTINCT a.Id) AS TotalAnswers,
    AVG(p.Score) AS AvgQuestionScore,
    AVG(a.Score) AS AvgAnswerScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT pl.Id) AS LinkCount
FROM
    Users u
LEFT JOIN
    Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN
    Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
LEFT JOIN
    Votes v ON v.PostId IN (p.Id, a.Id) AND v.UserId = u.Id
LEFT JOIN
    Badges b ON b.UserId = u.Id
LEFT JOIN
    Comments c ON c.UserId = u.Id
LEFT JOIN
    PostLinks pl ON pl.PostId = p.Id OR pl.RelatedPostId = p.Id
WHERE
    u.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
GROUP BY
    u.Id, u.DisplayName
ORDER BY
    TotalQuestions DESC
LIMIT 10;