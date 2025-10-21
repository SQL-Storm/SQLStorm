WITH HighReputationUsers AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation
    FROM 
        Users U
    WHERE 
        U.Reputation > 5000
),
PopularTags AS (
    SELECT 
        T.TagName,
        COUNT(DISTINCT P.Id) AS TagUsageCount
    FROM 
        Tags T
    LEFT JOIN 
        Posts P ON T.ExcerptPostId = P.Id
    WHERE 
        T.IsModeratorOnly = false AND T.IsRequired = false
    GROUP BY 
        T.TagName
    HAVING 
        COUNT(DISTINCT P.Id) > 50
),
RecentlyActiveQuestions AS (
    SELECT 
        P.Id AS QuestionId,
        P.Title,
        P.CreationDate,
        P.ViewCount,
        ROW_NUMBER() OVER (ORDER BY P.CreationDate DESC) AS RowNum
    FROM 
        Posts P
    WHERE 
        P.PostTypeId = 1
)
SELECT 
    HA.UserId,
    HA.DisplayName,
    HA.Reputation,
    PA.TagName,
    (CASE WHEN RQ.Title IS NOT NULL THEN RQ.Title ELSE '' END || ' [Views: ' || CAST(RQ.ViewCount AS VARCHAR) || ']') AS RecentlyActiveQuestion
FROM 
    HighReputationUsers HA
LEFT JOIN 
    Posts P ON HA.UserId = P.OwnerUserId
LEFT JOIN 
    LATERAL (
        SELECT 
            PT.TagName
        FROM 
            PopularTags PT
        WHERE 
            P.Tags LIKE '%' || PT.TagName || '%'
        ORDER BY 
            PT.TagUsageCount DESC
        LIMIT 1
    ) PA ON TRUE
JOIN 
    RecentlyActiveQuestions RQ ON RQ.RowNum <= 10
WHERE 
    P.PostTypeId = 2 
    AND COALESCE(P.Score, 0) > 10
    AND EXISTS (
        SELECT 1 FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2 AND V.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
    )
ORDER BY 
    HA.Reputation DESC, PA.TagName, RQ.CreationDate DESC;