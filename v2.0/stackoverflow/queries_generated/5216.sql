-- {"query": "5216.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 466} 
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(b.CountBadges, 0) AS BadgeCount,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
    AVG(COALESCE(v2.CreationDate - u.CreationDate, INTERVAL '0 days')) AS AvgTimeToFirstPostDays,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(DISTINCT a.Id) FILTER (WHERE a.PostTypeId = 2) AS AnswerCount,
    MAX(p.LastActivityDate) AS LastActivity,
    STRING_AGG(DISTINCT t3.Name, ',') AS TopTagNames
FROM
    Users u
LEFT JOIN (
    SELECT UserId, COUNT(*) AS CountBadges
    FROM Badges
    GROUP BY UserId
) b ON b.UserId = u.Id
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Posts a ON a.OwnerUserId = u.Id -- placeholder for potential joined alias, not required in all rows
LEFT JOIN Votes v ON v.UserId = u.Id
LEFT JOIN Votes v2 ON v2.UserId = u.Id AND v2.VoteTypeId = 2
LEFT JOIN LATERAL (
    SELECT UNNEST(string_to_array(p.Tags, '>')) AS tag
) t ON true
LEFT JOIN Tags t2 ON t2.TagName = t.tag
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
LEFT JOIN Posts t3 ON t3.Id = pl.RelatedPostId
WHERE
    u.AccountId IS NOT NULL
    AND u.Location IS NOT NULL
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
ORDER BY
    UpVotesReceived DESC, u.Reputation DESC
LIMIT 100;