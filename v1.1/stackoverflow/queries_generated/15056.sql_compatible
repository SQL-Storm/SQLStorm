WITH QuestionRanking AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score, 
        p.ViewCount,
        p.AnswerCount,
        DENSE_RANK() OVER (
            PARTITION BY 
                EXTRACT(YEAR FROM p.CreationDate), 
                CASE 
                    WHEN LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1 > 3 THEN 'Complex'
                    ELSE 'Simple'
                END 
            ORDER BY 
                p.Score * COALESCE(p.ViewCount, 1) DESC
        ) AS YearlyTagComplexityRank,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentTotal,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 1 
            ELSE 0 
        END AS IsClosed
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate > '2015-01-01'
        AND p.ViewCount > 100
),
UserContribution AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(p.Score) AS TotalQuestionScore,
        AVG(p.AnswerCount) AS AvgAnswersPerQuestion
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName
)
SELECT 
    qr.Title,
    qr.Score,
    qr.ViewCount,
    qr.YearlyTagComplexityRank,
    uc.DisplayName,
    uc.QuestionCount,
    qr.CommentTotal,
    qr.IsClosed,
    CAST(ROUND(
        CAST(qr.Score AS numeric) * LOG(CAST(qr.ViewCount AS numeric) + 1) * 
        (1.0 / (qr.YearlyTagComplexityRank + 1)) * 
        (CASE WHEN qr.IsClosed = 0 THEN 1.2 ELSE 0.8 END)
    , 2) AS numeric) AS ComplexityScore
FROM 
    QuestionRanking qr
JOIN 
    UserContribution uc ON EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.Id = qr.Id AND p.OwnerUserId = uc.UserId
    )
WHERE 
    qr.YearlyTagComplexityRank <= 10
    AND uc.QuestionCount > 5
    AND qr.CommentTotal > 0
GROUP BY
    qr.Title,
    qr.Score,
    qr.ViewCount,
    qr.YearlyTagComplexityRank,
    uc.DisplayName,
    uc.QuestionCount,
    qr.CommentTotal,
    qr.IsClosed
ORDER BY 
    ComplexityScore DESC
LIMIT 100;