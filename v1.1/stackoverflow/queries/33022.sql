-- {"query": "33022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 293} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalQuestions,
    COUNT(DISTINCT a.Id) AS TotalAnswers,
    AVG(p.Score) AS AvgQuestionScore,
    AVG(a.Score) AS AvgAnswerScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
    COUNT(DISTINCT b.Id) AS BadgesEarned,
    COUNT(DISTINCT c.Id) AS CommentsMade,
    COUNT(DISTINCT l.Id) AS LinkCount,
    MAX(p.CreationDate) AS LastQuestionDate,
    MAX(a.CreationDate) AS LastAnswerDate
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostLinks l ON u.Id = l.PostId
GROUP BY u.Id, u.DisplayName
ORDER BY TotalQuestions DESC, TotalAnswers DESC
LIMIT 100;