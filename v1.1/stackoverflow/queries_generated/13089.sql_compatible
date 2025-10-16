WITH RankedUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScore
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6' MONTH)
    GROUP BY 
        u.Id,
        u.DisplayName,
        u.Reputation
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.Tags,
        COUNT(DISTINCT ph.UserId) AS EditorCount,
        STRING_AGG(DISTINCT t.TagName, ', ') AS TagNames
    FROM 
        Posts p
    JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN 
        Tags t ON p.Tags LIKE ('%<' || t.TagName || '>%')
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
        AND p.ClosedDate IS NULL
    GROUP BY 
        p.Id,
        p.Title,
        p.Score,
        p.Tags
    HAVING 
        COUNT(DISTINCT ph.UserId) > 3
    ORDER BY 
        p.Score DESC
    LIMIT 10
),
AnswerQuality AS (
    SELECT 
        p.ParentId AS QuestionId,
        AVG(p.Score) AS AvgAnswerScore,
        MAX(p.Score) AS MaxAnswerScore
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 2
    GROUP BY 
        p.ParentId
)
SELECT 
    ru.DisplayName,
    ru.Reputation,
    tq.Title AS TopQuestionTitle,
    tq.Score AS TopQuestionScore,
    tq.EditorCount,
    aq.AvgAnswerScore,
    aq.MaxAnswerScore,
    CASE 
        WHEN ru.UserRank <= 10 THEN 'Top Contributor'
        WHEN ru.UserRank BETWEEN 11 AND 100 THEN 'Active Contributor'
        ELSE 'Contributor'
    END AS ContributorStatus
FROM 
    RankedUsers ru
JOIN 
    TopQuestions tq ON POSITION(',' || CAST(ru.Id AS VARCHAR) || ',' IN ',' || COALESCE(tq.Tags, '') || ',') > 0
LEFT JOIN 
    AnswerQuality aq ON tq.Id = aq.QuestionId
WHERE 
    ru.TotalPosts >= 50 
    AND (tq.Score * 1.5 + COALESCE(aq.AvgAnswerScore, 0)) > 100
ORDER BY 
    ru.UserRank,
    tq.Score DESC;