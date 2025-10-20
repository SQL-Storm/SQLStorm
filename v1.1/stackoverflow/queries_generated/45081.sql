-- {"query": "45081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 185814, "output_tokens": 32551} 
WITH TopActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(p.Score) AS AveragePostScore,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank
    FROM 
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE 
        u.Reputation > 1000
        AND p.CreationDate > TIMESTAMP '2015-01-01'
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        COUNT(DISTINCT p.Id) > 10
), 
TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS TagPostCount,
        AVG(p.Score) AS AverageTagScore,
        MAX(p.ViewCount) AS MaxTagViewCount
    FROM 
        Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.TagName
)
SELECT 
    tau.Id AS UserId,
    tau.DisplayName,
    tau.PostCount,
    tau.VoteCount,
    tau.AveragePostScore,
    tp.TagName,
    tp.TagPostCount,
    tp.AverageTagScore
FROM 
    TopActiveUsers tau
CROSS JOIN 
    TagPopularity tp
WHERE 
    tau.PostRank <= 100
    AND tp.TagPostCount > 50
ORDER BY 
    tau.PostCount * tp.TagPostCount DESC
LIMIT 1000;