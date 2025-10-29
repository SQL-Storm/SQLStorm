-- {"query": "5668.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 336} 
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(p.Id) AS PostCount,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    MAX(p.LastActivityDate) AS LastActive,
    AVG(p.Score) AS AvgPostScore,
    STRING_AGG(DISTINCT t.Name, ',') AS Tropes
FROM
    Users u
LEFT JOIN
    Posts p ON p.OwnerUserId = u.Id
LEFT JOIN
    (SELECT DISTINCT Id, Name FROM PostTypes) t ON p.PostTypeId = t.Id
LEFT JOIN
    LATERAL (
        SELECT
            pv2.VoteTypeId,
            COUNT(*) AS Cnt
        FROM Votes pv2
        WHERE pv2.PostId = p.Id
        GROUP BY pv2.VoteTypeId
    ) AS v ON TRUE
GROUP BY
    u.Id, u.DisplayName, u.Reputation
HAVING
    COUNT(p.Id) > 50 OR SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) > 5
ORDER BY
    CASE
        WHEN COUNT(p.Id) > 0 THEN SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) / COUNT(p.Id)
        ELSE 0
    END DESC,
    MAX(p.LastActivityDate) DESC
LIMIT 100;