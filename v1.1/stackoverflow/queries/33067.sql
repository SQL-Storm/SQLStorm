-- {"query": "33067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 357} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p1.Id) AS QuestionsCount,
    COUNT(DISTINCT p2.Id) AS AnswersCount,
    AVG(p1.Score) FILTER (WHERE p1.PostTypeId = 1) AS AvgQuestionScore,
    AVG(p2.Score) FILTER (WHERE p2.PostTypeId = 2) AS AvgAnswerScore,
    COUNT(DISTINCT c.Id) AS TotalComments,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
    COUNT(DISTINCT b.Id) AS BadgesEarned,
    COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount
FROM
    Users u
LEFT JOIN
    Posts p1 ON p1.OwnerUserId = u.Id AND p1.PostTypeId = 1
LEFT JOIN
    Posts p2 ON p2.OwnerUserId = u.Id AND p2.PostTypeId = 2
LEFT JOIN
    Comments c ON c.UserId = u.Id
LEFT JOIN
    Votes v ON v.UserId = u.Id
LEFT JOIN
    Badges b ON b.UserId = u.Id
LEFT JOIN
    PostLinks pl ON pl.PostId = u.Id
WHERE
    u.CreationDate > '2020-01-01'
    AND u.LastAccessDate > '2023-01-01'
GROUP BY
    u.Id, u.DisplayName
ORDER BY
    UpVotesReceived DESC, DownVotesReceived ASC
LIMIT 50;