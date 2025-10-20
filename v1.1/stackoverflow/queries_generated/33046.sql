-- {"query": "33046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 308} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT( DISTINCT p.Id) AS QuestionsCount,
    COUNT( DISTINCT a.Id) AS AnswersCount,
    AVG(p.Score) AS AvgQuestionScore,
    AVG(a.Score) AS AvgAnswerScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
    COUNT(DISTINCT b.Id) AS BadgesCount,
    MAX(u.LastAccessDate) AS LastActiveDate,
    COUNT(DISTINCT c.Id) AS CommentsMade,
    COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
    COUNT(DISTINCT p.Tags) AS UniqueTagsCount
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
LEFT JOIN Votes v ON v.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN PostLinks pl ON pl.PostId IN (p.Id, a.Id)
GROUP BY u.Id, u.DisplayName
HAVING COUNT( DISTINCT p.Id) > 10
ORDER BY LastActiveDate DESC
LIMIT 100;