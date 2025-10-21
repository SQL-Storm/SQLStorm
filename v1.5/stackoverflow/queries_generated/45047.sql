-- {"query": "45047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 107818, "output_tokens": 19146} 
WITH PostPopularity AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentVolume,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(u.Reputation) AS AverageUserReputation,
        t.TagName
    FROM 
        Posts p
    JOIN 
        PostLinks pl ON p.Id = pl.PostId
    JOIN 
        Votes v ON p.Id = v.PostId
    JOIN 
        Comments c ON p.Id = c.PostId
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    JOIN 
        Tags t ON SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2) = t.TagName
    WHERE 
        p.PostTypeId = 1
        AND p.CreationDate > '2015-01-01'
        AND p.Score > 10
    GROUP BY 
        p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, t.TagName
    HAVING 
        COUNT(DISTINCT v.Id) > 50
)
SELECT 
    TagName,
    MAX(Score) AS MaxScore,
    AVG(ViewCount) AS AvgViews,
    SUM(AnswerCount) AS TotalAnswers,
    COUNT(*) AS PopularPostCount
FROM 
    PostPopularity
WHERE 
    AverageUserReputation > 1000
GROUP BY 
    TagName
ORDER BY 
    TotalAnswers DESC, 
    AvgViews DESC
LIMIT 100;