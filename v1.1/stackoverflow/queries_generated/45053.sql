-- {"query": "45053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 424}
WITH UserPostScores AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        pt.Name AS PostType, 
        SUM(p.Score) AS TotalScore,
        COUNT(p.Id) AS PostCount,
        RANK() OVER (PARTITION BY pt.Name ORDER BY SUM(p.Score) DESC) AS ScoreRank
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    WHERE 
        u.Reputation > 1000 
        AND p.CreationDate > '2015-01-01'
    GROUP BY 
        u.Id, u.DisplayName, pt.Name
),
TagPopularity AS (
    SELECT 
        unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagCount,
        AVG(Score) AS AvgTagScore
    FROM 
        Posts
    WHERE 
        Tags IS NOT NULL
    GROUP BY 
        Tag
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.PostType,
    ups.TotalScore,
    ups.PostCount,
    ups.ScoreRank,
    tp.Tag,
    tp.TagCount,
    tp.AvgTagScore
FROM 
    UserPostScores ups
JOIN 
    TagPopularity tp ON 1=1
WHERE 
    ups.ScoreRank <= 10
ORDER BY 
    ups.TotalScore DESC, 
    tp.TagCount DESC
LIMIT 100;
