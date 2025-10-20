-- {"query": "33070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 277} 
SELECT 
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(p.Id) AS TotalQuestions,
    AVG(p.Score) AS AvgQuestionScore,
    SUM(CASE WHEN p.CreationDate >= NOW() - INTERVAL '1 year' THEN 1 ELSE 0 END) AS QuestionsLastYear,
    COUNT(c.Id) AS TotalComments,
    AVG(c.Score) AS AvgCommentScore,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
    COUNT(vs.Id) AS TotalVotesReceived,
    COUNT(b.Id) AS BadgesEarned,
    MAX(p.LastActivityDate) AS LastActivityDate
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN Votes vs ON p.Id = vs.PostId
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE u.CreationDate <= NOW() - INTERVAL '1 year'
GROUP BY u.Id, u.DisplayName, u.Reputation
ORDER BY TotalQuestions DESC
LIMIT 50;