-- {"query": "33081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 328} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT q.Id) AS QuestionsCount,
    COUNT(DISTINCT a.Id) AS AnswersCount,
    AVG(p.Score) AS AvgPostScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
    COUNT(DISTINCT b.Id) AS BadgesCount,
    COUNT(DISTINCT c.Id) AS CommentsCount,
    MAX(p.CreationDate) AS LastPostDate,
    COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount
FROM
    Users u
LEFT JOIN
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN
    Posts q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1
LEFT JOIN
    Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
LEFT JOIN
    Votes v ON u.Id = v.UserId
LEFT JOIN
    Badges b ON u.Id = b.UserId
LEFT JOIN
    Comments c ON u.Id = c.UserId
LEFT JOIN
    PostLinks pl ON p.Id = pl.PostId
GROUP BY
    u.Id, u.DisplayName, u.Reputation
ORDER BY
    u.Reputation DESC, TotalPosts DESC
LIMIT 100;