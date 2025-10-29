-- {"query": "5153.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 280} 
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    AVG(CASE WHEN v.VoteTypeId IN (2,3) THEN v.BountyAmount ELSE NULL END) AS AvgVoteWeight
FROM
    Users u
LEFT JOIN
    Posts p ON p.OwnerUserId = u.Id
LEFT JOIN
    Votes v ON v.PostId = p.Id
    AND v.VoteTypeId IN (2,3)
LEFT JOIN
    PostLinks pl ON pl.PostId = p.Id
LEFT JOIN
    PostLinks pl2 ON pl2.RelatedPostId = p.Id
WHERE
    u.Reputation > 1000
    OR EXISTS (
        SELECT 1
        FROM Badges b
        WHERE b.UserId = u.Id
          AND b.Class = 1
    )
GROUP BY
    u.Id, u.DisplayName
HAVING
    COUNT(DISTINCT p.Id) > 5
ORDER BY
    PostCount DESC, UserName ASC
LIMIT 100;