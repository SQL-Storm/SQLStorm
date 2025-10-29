-- {"query": "45019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 238}
WITH TopTagUsers AS (
    SELECT t.TagName, 
           u.Id, 
           u.DisplayName, 
           COUNT(p.Id) AS PostCount,
           SUM(p.Score) AS TotalScore,
           RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(p.Id) DESC) AS UserTagRank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE t.Count > 1000 AND p.PostTypeId = 1
    GROUP BY t.TagName, u.Id, u.DisplayName
)
SELECT 
    TagName, 
    Id, 
    DisplayName, 
    PostCount, 
    TotalScore,
    UserTagRank
FROM TopTagUsers
WHERE UserTagRank <= 5
ORDER BY TagName, PostCount DESC
LIMIT 100;
