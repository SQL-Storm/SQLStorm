-- {"query": "13091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 658} 

WITH UserActivity AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
        AVG(p.Score) AS AvgScore,
        MAX(b.Date) AS LastBadgeDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS UserRank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 1000 
        AND p.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 
        u.Id
),
PostEngagement AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COUNT(DISTINCT ph.Id) AS EditCount,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE 
        p.PostTypeId = 1
        AND p.ClosedDate IS NULL
    GROUP BY 
        p.Id
)
SELECT 
    ua.DisplayName,
    ua.PostsCount,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.AvgScore,
    pe.Title,
    pe.Score,
    pe.ViewCount,
    pe.AnswerCount,
    pe.CommentCount,
    pe.EditCount,
    CAST(pe.Score AS float) / NULLIF(pe.PreviousPostScore, 1) AS ScoreRatio,
    STRING_AGG(DISTINCT t.TagName, ', ') WITHIN GROUP (ORDER BY t.TagName) AS TagList
FROM 
    UserActivity ua
JOIN 
    PostEngagement pe ON ua.Id = pe.OwnerUserId
LEFT JOIN 
    PostsTags pt ON pe.Id = pt.PostId
LEFT JOIN 
    Tags t ON pt.TagId = t.Id
WHERE 
    ua.UserRank <= 100
GROUP BY 
    ua.Id, pe.Id
ORDER BY 
    ua.UserRank, pe.Score DESC;
