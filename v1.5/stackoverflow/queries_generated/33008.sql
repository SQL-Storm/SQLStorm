-- {"query": "33008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 351} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    AVG(p.Score) AS AvgQuestionScore,
    MAX(p.CreationDate) AS LastQuestionDate,
    COUNT(DISTINCT a.Id) AS AnswerCount,
    AVG(a.Score) AS AvgAnswerScore,
    COUNT(DISTINCT c.Id) AS CommentCount,
    AVG(c.Score) AS AvgCommentScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT wl.RelatedPostId) AS LinkCount,
    SUM(CASE WHEN hv.PostHistoryTypeId IN (4, 6) THEN 1 ELSE 0 END) AS NumberOfQuestionEdits
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN PostLinks wl ON wl.PostId IN (p.Id, a.Id) AND wl.RelatedPostId IS NOT NULL
LEFT JOIN PostHistory hv ON hv.UserId = u.Id
GROUP BY u.Id, u.DisplayName
ORDER BY TotalUpVotes DESC, QuestionCount DESC
LIMIT 50;