-- {"query": "54061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2714} 
SELECT
    t.TagName,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS Questions,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS Answers,
    SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS TotalScore,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgScore,
    SUM(CASE WHEN ph.Id IS NOT NULL THEN 1 ELSE 0 END) AS Edits,
    COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    AVG(u.Reputation) AS AvgReputation,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.UserId END) AS GoldBadges,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score)
            FILTER (WHERE p.PostTypeId = 1),
        2
    ) AS MedianScore
FROM Tags t
LEFT JOIN LATERAL (
    SELECT *
    FROM Posts p
    WHERE POSITION('<' || t.TagName || '>' IN p.Tags) > 0
) p ON true
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Users u ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON b.UserId = u.Id
GROUP BY t.TagName
HAVING COUNT(*) > 100
ORDER BY Questions DESC
LIMIT 50;