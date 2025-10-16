-- {"query": "13058.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 655} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (5, 8) THEN 1 ELSE 0 END) AS EditsCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.UserId = u.Id
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName
),
RankedUsers AS (
    SELECT 
        UserId,
        DisplayName,
        PostsCount,
        TotalScore,
        LastPostDate,
        EditsCount,
        RANK() OVER (ORDER BY TotalScore DESC, PostsCount DESC) AS Rank
    FROM 
        UserActivity
    WHERE 
        PostsCount > 5 AND EditsCount >= 2
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS QuestionsCount,
        AVG(p.Score) AS AvgQuestionScore,
        MAX(p.CreationDate) AS LastQuestionDate
    FROM 
        Tags t
    JOIN 
        Posts p ON POSITION(t.TagName IN p.Tags) > 0
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.TagName
    HAVING 
        COUNT(p.Id) > 10
    ORDER BY 
        AvgQuestionScore DESC
    LIMIT 
        10
)
SELECT 
    ru.DisplayName,
    ru.PostsCount,
    ru.TotalScore,
    ru.LastPostDate,
    ru.EditsCount,
    tt.TagName,
    tt.QuestionsCount,
    tt.AvgQuestionScore,
    tt.LastQuestionDate
FROM 
    RankedUsers ru
LEFT JOIN 
    Posts p ON ru.UserId = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN 
    Tags t ON POSITION(t.TagName IN p.Tags) > 0
LEFT JOIN 
    TopTags tt ON t.TagName = tt.TagName
WHERE 
    ru.Rank <= 50
    AND (tt.TagName IS NOT NULL OR p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months')
    AND (p.AcceptedAnswerId IS NOT NULL OR p.AnswerCount > 0)
ORDER BY 
    ru.Rank ASC, tt.AvgQuestionScore DESC NULLS LAST;