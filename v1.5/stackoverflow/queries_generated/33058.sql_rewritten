-- {"query": "33058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 298} 
SELECT
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(p.Id) AS TotalQuestions,
    AVG(p.Score) AS AvgQuestionScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
    COUNT(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 END) AS QuestionsWithAcceptedAnswer,
    COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT pb.Id) AS BadgesCount
FROM
    Users u
LEFT JOIN
    Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN
    Votes v ON p.Id = v.PostId AND v.UserId = u.Id
LEFT JOIN
    PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1
LEFT JOIN
    Comments c ON p.Id = c.PostId
LEFT JOIN
    Badges pb ON u.Id = pb.UserId
WHERE
    u.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
GROUP BY
    u.Id, u.DisplayName, u.Reputation
ORDER BY
    TotalQuestions DESC
LIMIT 100;