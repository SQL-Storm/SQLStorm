-- {"query": "33098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 370} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT q.Id) AS QuestionsPosted,
    COUNT(DISTINCT a.Id) AS AnswersPosted,
    AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    COUNT(DISTINCT c.Id) AS TotalComments,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
    MAX(p.LastActivityDate) AS LastActive,
    COUNT(DISTINCT b.Id) AS BadgesEarned,
    COUNT(DISTINCT pl.Id) AS TotalLinks,
    COUNT(DISTINCT ph.Id) AS EditHistoryCount
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Posts q ON p.PostTypeId = 1 AND p.OwnerUserId = u.Id
LEFT JOIN Posts a ON p.PostTypeId = 2 AND p.OwnerUserId = u.Id
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
GROUP BY u.Id, u.DisplayName
ORDER BY TotalPosts DESC
LIMIT 100;