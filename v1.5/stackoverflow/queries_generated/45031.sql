-- {"query": "45031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 71114, "output_tokens": 12802} 
WITH UserTagActivity AS (
    SELECT 
        u.Id AS UserId, 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalTagScore,
        AVG(p.ViewCount) AS AvgViewCount,
        MAX(p.CreationDate) AS LatestPostDate
    FROM 
        Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    CROSS JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS tag
    JOIN Tags t ON t.TagName = tag
    WHERE 
        p.PostTypeId IN (1,2)
        AND u.Reputation > 1000
    GROUP BY 
        u.Id, t.TagName
), RankedUserTags AS (
    SELECT 
        UserId, 
        TagName,
        PostCount,
        TotalTagScore,
        AvgViewCount,
        LatestPostDate,
        DENSE_RANK() OVER (PARTITION BY UserId ORDER BY PostCount DESC, TotalTagScore DESC) AS TagRank
    FROM 
        UserTagActivity
)
SELECT 
    r.UserId,
    r.TagName,
    r.PostCount,
    r.TotalTagScore,
    r.AvgViewCount,
    r.LatestPostDate,
    b.Name AS TopBadge,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = r.UserId AND v.VoteTypeId = 2) AS UpvoteCount
FROM 
    RankedUserTags r
JOIN Users u ON r.UserId = u.Id
LEFT JOIN (
    SELECT 
        UserId, 
        Name 
    FROM Badges 
    WHERE Class = 1
    GROUP BY UserId, Name
) b ON r.UserId = b.UserId
WHERE 
    r.TagRank <= 3
    AND r.PostCount > 5
ORDER BY 
    r.PostCount DESC, 
    r.TotalTagScore DESC
LIMIT 1000;