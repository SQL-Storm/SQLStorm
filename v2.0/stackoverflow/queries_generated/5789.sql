-- {"query": "5789.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 594} 
SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.PostTypeId,
    COALESCE(p.Tags, '') AS Tags,
    u.DisplayName AS Owner,
    u.Reputation,
    COUNT(DISTINCT c.Id) AS CommentCount,
    AVG(vm.CalcScore) OVER (PARTITION BY p.Id) AS AvgVoteScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    MAX(p.LastActivityDate) AS LastActivityDate,
    b.Name AS BadgeName,
    bl.TotalBadges,
    CASE
        WHEN p.Score IS NULL THEN 0
        ELSE p.Score * 1.0
    END / NULLIF(p.ViewCount, 0) AS ScorePerView,
    ARRAY_AGG(DISTINCT lt.Name) FILTER (WHERE lnk.LinkTypeId = 1) AS LinkedPostTitles,
    (SELECT COUNT(*) FROM Posts AS p2 WHERE p2.OwnerUserId = p.OwnerUserId AND p2.Id <> p.Id) AS OtherPostsByOwner
FROM
    Posts p
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    (SELECT PostId, AVG(CASE WHEN VoteTypeId = 2 THEN 1 ELSE -1 END) AS CalcScore
     FROM Votes
     GROUP BY PostId) AS vm ON vm.PostId = p.Id
LEFT JOIN
    PostLinks lnk ON lnk.PostId = p.Id
LEFT JOIN
    Posts pl ON lnk.RelatedPostId = pl.Id
LEFT JOIN
    Badges b ON b.UserId = p.OwnerUserId
LEFT JOIN
    (SELECT UserId, COUNT(*) AS TotalBadges
       FROM Badges
       GROUP BY UserId) AS bl ON bl.UserId = p.OwnerUserId
LEFT JOIN
    LinkTypes lt ON lnk.LinkTypeId = lt.Id
WHERE
    p.PostTypeId IN (1, 2) -- Questions and Answers
    AND p.ClosedDate IS NULL
    AND (p.LastActivityDate > p.CreationDate - INTERVAL '30 days')
GROUP BY
    p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.PostTypeId, p.Tags,
    u.DisplayName, u.Reputation, b.Name, bl.TotalBadges
ORDER BY
    LastActivityDate DESC, p.Score DESC
LIMIT 100;