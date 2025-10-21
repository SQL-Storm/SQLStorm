-- {"query": "33025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 333} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalQuestions,
    COUNT(DISTINCT a.Id) AS TotalAnswers,
    AVG(p.Score) AS AvgQuestionScore,
    AVG(a.Score) AS AvgAnswerScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
    COUNT(DISTINCT c.Id) AS TotalCommentsMade,
    COUNT(DISTINCT badges.Id) AS BadgeCount,
    SUM(CASE WHEN p.Tags LIKE '%<performance>%' THEN 1 ELSE 0 END) AS QuestionsTaggedPerformance,
    SUM(CASE WHEN a.Tags LIKE '%<performance>%' THEN 1 ELSE 0 END) AS AnswersTaggedPerformance
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Badges badges ON u.Id = badges.UserId
LEFT JOIN Posts pa ON a.Id = pa.ParentId
WHERE u.CreationDate < '2020-01-01'
GROUP BY u.Id, u.DisplayName
ORDER BY TotalQuestions DESC, UpVotesReceived DESC
LIMIT 100;