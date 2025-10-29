-- {"query": "5090.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 391} 
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COALESCE(u.Location, 'Unknown') AS Location,
    COALESCE(u.WebsiteUrl, '') AS Website,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    AVG(CASE WHEN v.VoteTypeId = 2 THEN 1.0 ELSE 0 END) * 1.0 AS AvgUpvotesPerPost,
    MAX(p.LastActivityDate) AS LastActive,
    SUM(COALESCE(v.BountyAmount, 0)) AS TotalBountiesAwarded,
    STRING_AGG(DISTINCT tt.Name, ',') FILTER (WHERE tt.Name IS NOT NULL) AS HistoryTypesSeen,
    CASE
        WHEN u.AccountId IS NULL THEN 'NoAccount'
        ELSE 'AccountLinked'
    END AS AccountStatus
FROM
    Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
LEFT JOIN (SELECT DISTINCT Name FROM PostHistoryTypes) AS tt ON tt.Name IS NOT NULL
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.WebsiteUrl, u.AccountId
HAVING
    COUNT(DISTINCT p.Id) > 0
ORDER BY
    TotalPosts DESC, u.Reputation DESC
LIMIT 100;