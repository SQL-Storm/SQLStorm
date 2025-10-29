-- {"query": "5877.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 447} 
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostsCreated,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LastActive,
    STRING_AGG(DISTINCT t.Name, ',') FILTER (WHERE t.Name IS NOT NULL) AS TagsSubset,
    COALESCE(b.TotalBadges, 0) AS TotalBadges,
    COALESCE(v.Upvotes, 0) AS Upvotes,
    COALESCE(v.Downvotes, 0) AS Downvotes
FROM
    Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
        SELECT STRING_AGG(Name, ',') AS Name
        FROM Tags tg
        WHERE tg.Id IN (
            SELECT TagId FROM UNNEST(string_to_array(p.Tags, ',')::int[])
        )
    ) t ON true
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS TotalBadges
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS Upvotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS Downvotes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY UserId
    ) v ON v.UserId = u.Id
WHERE
    u.AccountId IS NOT NULL
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.AccountId
HAVING
    COUNT(p.Id) > 0
ORDER BY
    Upvotes DESC, LastActive DESC
LIMIT 100;