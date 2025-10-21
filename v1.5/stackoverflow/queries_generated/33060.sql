-- {"query": "33060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 452} 
SELECT
    u.Id AS UserID,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT q.Id) FILTER (WHERE p.PostTypeId = 1) AS Questions,
    COUNT(DISTINCT a.Id) FILTER (WHERE p.PostTypeId = 2) AS Answers,
    AVG(p.Score) AS AveragePostScore,
    SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes,
    COUNT(DISTINCT c.Id) AS CommentsMade,
    MAX(p.CreationDate) AS LastActivity,
    COUNT(DISTINCT b.Id) AS BadgesEarned,
    COUNT(DISTINCT v2.Id) FILTER (WHERE v2.VoteTypeId = 2) AS UpVotes,
    COUNT(DISTINCT v3.Id) FILTER (WHERE v3.VoteTypeId = 3) AS DownVotes,
    STRING_AGG(DISTINCT t.TagName, ',') AS TopTags
FROM
    Users u
LEFT JOIN
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN
    Posts q ON p.PostTypeId = 1 AND q.Id = p.Id
LEFT JOIN
    Posts a ON p.PostTypeId = 2 AND a.Id = p.Id
LEFT JOIN
    Comments c ON u.Id = c.UserId
LEFT JOIN
    Badges b ON u.Id = b.UserId
LEFT JOIN
    Votes v ON u.Id = v.UserId
LEFT JOIN
    Votes v2 ON v2.PostId = p.Id AND v2.VoteTypeId = 2
LEFT JOIN
    Votes v3 ON v3.PostId = p.Id AND v3.VoteTypeId = 3
LEFT JOIN
    Posts p_tags ON p.PostTypeId = 1
LEFT JOIN
    PostTags pt ON p_tags.Id = pt.PostId
LEFT JOIN
    Tags t ON pt.TagId = t.Id
GROUP BY
    u.Id, u.DisplayName, u.Reputation
ORDER BY
    u.Reputation DESC
LIMIT 100;