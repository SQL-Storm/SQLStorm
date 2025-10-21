-- {"query": "6084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 345} 
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostCount,
    AVG(p.Score) AS AvgPostScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    MAX(p.LastActivityDate) AS LastActive,
    STRING_AGG(DISTINCT t.Name, ',') AS TagsInvolvement,
    COALESCE(SUM(v.BountyAmount), 0) AS TotalBountiesAwarded,
    MAX(CASE WHEN b.Id IS NOT NULL THEN b.Date ELSE NULL END) AS LastBadgeDate
FROM
    Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2 -- UpMod
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
LEFT JOIN Tags t ON t.Id IN (
        SELECT
            CAST(z.value AS int)
        FROM
            (SELECT unnest(string_to_array(p.Tags, '><')) AS value) z
        WHERE
            z.value ~ '^\d+$'
    )
LEFT JOIN Badges b ON b.UserId = u.Id
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.AccountId
HAVING
    COUNT(DISTINCT p.Id) > 0
ORDER BY
    Reputation DESC,
    LastActive DESC
LIMIT 100;