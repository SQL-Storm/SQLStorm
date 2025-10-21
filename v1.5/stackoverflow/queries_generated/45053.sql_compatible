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
        AND p.CreationDate > DATE '2015-01-01'
    GROUP BY 
        u.Id, u.DisplayName, pt.Name
),
TagPopularity AS (
    SELECT 
        TRIM(BOTH '>< ' FROM SUBSTRING(Tags FROM 2 FOR LENGTH(Tags) - 2)) AS Tag,
        COUNT(*) AS TagCount,
        AVG(p.Score) AS AvgTagScore
    FROM 
        Posts p
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