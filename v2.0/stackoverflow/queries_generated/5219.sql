-- {"query": "5219.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 474} 
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(p.Id) AS PostsCreated,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    MAX(p.CreationDate) AS LastPostDate,
    AVG(COALESCE(p.Score,0)) AS AvgPostScore,
    STRING_AGG(DISTINCT t.Name, ',') AS TagNames,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesCast,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesCast,
    MAX(CASE WHEN b.Id IS NOT NULL THEN b.Date ELSE NULL END) AS LastBadgeDate,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
FROM
    Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN (
    SELECT
        pt.Id,
        pt.Name,
        pt.Id AS _ptid
    FROM PostHistoryTypes pt
) AS ht ON 1=1
LEFT JOIN Tags t ON t.Id = (SELECT TOP 1 t2.Id FROM Tags t2 WHERE t2.Count > 0 AND t2.ExcerptPostId = p.Id LIMIT 1)
LEFT JOIN Votes v ON v.UserId = u.Id
    AND v.PostId = p.Id
    AND v.CreationDate = (
        SELECT MAX(CreationDate)
        FROM Votes
        WHERE PostId = p.Id
    )
LEFT JOIN Badges b ON b.UserId = u.Id
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation
HAVING
    COUNT(p.Id) > 5
ORDER BY
    Reputation DESC,
    LastPostDate DESC
LIMIT 100;