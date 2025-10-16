WITH UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViews,
        MAX(p.CreationDate) AS LastPostDate,
        RANK() OVER (ORDER BY SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) DESC) AS QuestionScoreRank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.Reputation > 1000
        AND p.CreationDate BETWEEN DATE '2022-01-01' AND DATE '2023-01-01'
    GROUP BY 
        u.Id, u.DisplayName
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.OwnerUserId,
        ph.Comment AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    WHERE 
        p.PostTypeId = 1
        AND (p.Tags LIKE '%<performance>%' OR p.Tags LIKE '%<benchmarking>%')
)
SELECT 
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalQuestionViews,
    ua.AvgQuestionViews,
    ua.LastPostDate,
    tq.Title AS TopQuestionTitle,
    tq.Score AS TopQuestionScore,
    crt.Name AS CloseReason,
    ua.QuestionScoreRank
FROM 
    UserActivity ua
LEFT JOIN 
    TopQuestions tq ON ua.Id = tq.OwnerUserId AND tq.rn = 1
LEFT JOIN 
    CloseReasonTypes crt ON CAST(tq.CloseReason AS SMALLINT) = crt.Id
WHERE 
    ua.QuestionScoreRank <= 10
    OR (ua.TotalPosts > 50 AND ua.AvgQuestionViews > 1000)
GROUP BY
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalQuestionViews,
    ua.AvgQuestionViews,
    ua.LastPostDate,
    tq.Title,
    tq.Score,
    crt.Name,
    ua.QuestionScoreRank,
    tq.OwnerUserId,
    tq.rn
ORDER BY 
    ua.TotalQuestions DESC,
    ua.AvgQuestionViews DESC;