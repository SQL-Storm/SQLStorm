-- {"query": "6049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 355} 
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostCount,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
    MAX(p.CreationDate) AS LastPostDate,
    STRING_AGG(DISTINCT t.Name, ',') FILTER (WHERE t.Name IS NOT NULL) AS PostTypesInvolved,
    MAX(CASE WHEN b.Id IS NOT NULL THEN b.Date END) AS LastBadgeDate
FROM
    Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN (
    SELECT DISTINCT p2.Id, pt2.Name
    FROM Posts p2
    JOIN PostTypes pt2 ON p2.PostTypeId = pt2.Id
) t ON t.Id = p.Id
WHERE
    u.AccountId IS NOT NULL
GROUP BY
    u.Id, u.DisplayName, u.Reputation
HAVING
    COUNT(DISTINCT p.Id) > 0
ORDER BY
    u.Reputation DESC,
    PostCount DESC
LIMIT 100;