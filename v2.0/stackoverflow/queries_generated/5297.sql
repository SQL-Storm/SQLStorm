-- {"query": "5297.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 363} 
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    COUNT(DISTINCT p.Id) AS PostCount,
    AVG(p.Score) AS AvgPostScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
    MAX(p.CreationDate) AS LastPostDate,
    STRING_AGG(DISTINCT t.Name, ',') FILTER (WHERE t.Name IS NOT NULL) AS PostTags,
    SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCountOnUserPosts,
    SUM(CASE WHEN bh.PostHistoryTypeId IN (10, 11, 12, 13) THEN 1 ELSE 0 END) AS AdminModerationVotes
FROM
    Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
LEFT JOIN Tags t ON t.Id = COALESCE(p.Tags::int, 0) -- placeholder cast for tag retrieval
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN PostHistory bh ON bh.PostId = p.Id
WHERE
    u.Reputation > 1000
    AND p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY
    u.Id, u.DisplayName
HAVING
    COUNT(DISTINCT p.Id) > 0
ORDER BY
    PostCount DESC, LastPostDate DESC
LIMIT 100;