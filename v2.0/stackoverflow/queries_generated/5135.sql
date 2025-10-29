-- {"query": "5135.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 390} 
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN v.BountyAmount ELSE 0 END) AS TotalUpvoteBounty,
    MAX(p.LastActivityDate) AS LastActivity,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    STRING_AGG(DISTINCT t.Name, ',') AS TagsTouched,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS MaxQuestionViews
FROM
    Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN (
    SELECT
        pt.Id,
        pt.Name
    FROM PostTypes pt
) t ON t.Id = p.PostTypeId
WHERE
    u.Reputation > 1000
    AND u.CreationDate < CURRENT_DATE - INTERVAL '1 year'
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    AND (ph.PostHistoryTypeId IS NULL OR ph.PostHistoryTypeId NOT IN (50, 52))
GROUP BY
    u.Id, u.DisplayName, u.Reputation
ORDER BY
    RepSort := SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) DESC
LIMIT 100;