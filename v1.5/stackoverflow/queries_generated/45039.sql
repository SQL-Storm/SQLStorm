-- {"query": "45039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 262}
SELECT
    t.TagName,
    COUNT(p.Id) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViewCount,
    (
        SELECT COUNT(DISTINCT v.UserId)
        FROM Votes v
        JOIN Posts vp ON v.PostId = vp.Id
        WHERE vp.Tags LIKE '%' || t.TagName || '%'
        AND v.VoteTypeId = 2
    ) AS UniqueUpvoters,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.ViewCount) AS P75ViewCount
FROM
    Tags t
JOIN
    Posts p ON p.Tags LIKE '%' || t.TagName || '%'
WHERE
    p.PostTypeId = 1
    AND p.CreationDate > '2020-01-01'
GROUP BY
    t.TagName
HAVING
    COUNT(p.Id) > 100
ORDER BY
    UniqueUpvoters DESC, AvgScore DESC
LIMIT 50;
