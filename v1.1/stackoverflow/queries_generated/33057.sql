-- {"query": "33057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 424} 
SELECT
    u.DisplayName AS UserName,
    COUNT(p.Id) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    COUNT(DISTINCT cl.RelatedPostId) AS UniqueLinksCount,
    MAX(p.CreationDate) AS LastPostDate,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT c.Id) AS TotalComments,
    STRING_AGG(DISTINCT tt.Name, ', ') AS PostHistoryTypes,
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 3) AS BronzeBadges
FROM
    Users u
LEFT JOIN
    Posts p ON p.OwnerUserId = u.Id
LEFT JOIN
    PostLinks pl ON pl.PostId = p.Id
LEFT JOIN
    PostLinks pl2 ON pl2.RelatedPostId = p.Id
LEFT JOIN
    PostHistory ph ON ph.PostId = p.Id
LEFT JOIN
    PostHistoryTypes tt ON tt.Id = ph.PostHistoryTypeId
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
LEFT JOIN
    PostLinks cl ON cl.PostId = p.Id AND cl.LinkTypeId = 3
WHERE
    u.Reputation >= 1000
    AND u.CreationDate >= DATE '2010-01-01'
    AND p.PostTypeId IN (1, 2)
GROUP BY
    u.Id, u.DisplayName
ORDER BY
    TotalPosts DESC
LIMIT 10;