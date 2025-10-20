-- {"query": "33021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 336} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) AS TotalQuestions,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    COUNT(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 END) AS QuestionsWithAcceptedAnswer,
    SUM(p.ViewCount) AS TotalViewCount,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT b.Id) AS BadgesEarned,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesReceived,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesReceived,
    COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
    COUNT(DISTINCT t.TagName) AS UniqueTagsUsed,
    MAX(p.CreationDate) AS LastActivityDate
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1
LEFT JOIN Tagging tt ON p.Id = tt.PostId
LEFT JOIN Tags t ON tt.TagId = t.Id
GROUP BY u.Id, u.DisplayName
ORDER BY TotalQuestions DESC, AvgQuestionScore DESC
LIMIT 100;