-- {"query": "5083.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 380} 
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostCount,
    AVG(p.Score) AS AvgPostScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    MAX(p.CreationDate) AS LastActive,
    STRING_AGG(DISTINCT t.Name, ',') AS TagsOfQuestions
FROM
    Users u
LEFT JOIN
    Posts p ON p.OwnerUserId = u.Id
LEFT JOIN
    Tags t ON t.Id IN (
        SELECT
            CAST(x AS int)
        FROM
            UNNEST(STRING_TO_ARRAY(REPLACE(p.Tags, '><', ','), ',')) AS x
        WHERE
            x ~ '^[0-9]+$'
    )
LEFT JOIN
    PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 1
LEFT JOIN
    Posts_related pr ON pr.Id = pl.RelatedPostId
WHERE
    u.Reputation >= 1000
    OR EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1)
GROUP BY
    u.Id, u.DisplayName, u.Reputation
HAVING
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) > 0
ORDER BY
    LastActive DESC, RepoRankScore := (CAST(u.Reputation AS bigint) - COALESCE(AVG(p.Score)::bigint, 0)) DESC
OFFSET 0 ROWS FETCH FIRST 100 ROWS ONLY;