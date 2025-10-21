-- {"query": "33061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 331} 
SELECT
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(p.Id) AS TotalQuestions,
    AVG(p.Score) AS AvgQuestionScore,
    SUM(CASE WHEN p.Score >= 10 THEN 1 ELSE 0 END) AS QuestionsWithHighScore,
    COUNT(c.Id) AS TotalComments,
    AVG(c.Score) AS AvgCommentScore,
    COUNT(v.Id) AS TotalVotes,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
    COUNT(b.Id) AS TotalBadges,
    COUNT(DISTINCT PL.RelatedPostId) AS NumberOfLinkedPosts,
    MAX(p.CreationDate) AS LastQuestionDate,
    AVG(p.ViewCount) AS AvgViewCountPerQuestion
FROM
    Users u
LEFT JOIN
    Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN
    Comments c ON p.Id = c.PostId
LEFT JOIN
    Votes v ON p.Id = v.PostId
LEFT JOIN
    PostLinks PL ON p.Id = PL.PostId AND PL.LinkTypeId = 1
LEFT JOIN
    Badges b ON u.Id = b.UserId
WHERE
    u.Reputation > 1000 AND
    u.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
GROUP BY
    u.DisplayName,
    u.Reputation
ORDER BY
    TotalQuestions DESC
LIMIT 100;