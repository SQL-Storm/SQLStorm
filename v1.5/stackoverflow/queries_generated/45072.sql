-- {"query": "45072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 245}
SELECT
    t.TagName,
    COUNT(p.Id) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews,
    COUNT(DISTINCT v.UserId) AS UniqueVoters,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId IN (
        SELECT Id FROM Posts WHERE Tags LIKE '%' || t.TagName || '%'
    )) AS RelatedPostLinks
FROM
    Tags t
JOIN
    Posts p ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN
    Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
WHERE
    t.Count > 1000
    AND p.PostTypeId = 1
GROUP BY
    t.TagName
HAVING
    AVG(p.Score) > 3
ORDER BY
    PostCount DESC,
    UniqueVoters DESC
LIMIT 50;
