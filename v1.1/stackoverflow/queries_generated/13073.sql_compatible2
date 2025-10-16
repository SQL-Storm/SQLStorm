WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditsMade,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) DESC) AS RankByQuestions
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.UserId = u.Id
    WHERE 
        u.Reputation > 1000
        AND u.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
    GROUP BY 
        u.Id, u.DisplayName
),
TagAnalysis AS (
    SELECT 
        p.Tags,
        COUNT(*) AS PostCount,
        AVG(p.Score) AS AvgTagScore
    FROM 
        Posts p
    WHERE 
        p.Tags IS NOT NULL
        AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6' MONTH)
    GROUP BY 
        p.Tags
    HAVING 
        COUNT(*) > 10
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.QuestionsAsked,
    ua.AnswersProvided,
    ua.AvgPostScore,
    ua.EditsMade,
    ta.Tags,
    ta.PostCount,
    ta.AvgTagScore,
    (
        SELECT 
            COUNT(*) 
        FROM 
            Badges b 
        WHERE 
            b.UserId = ua.UserId AND b.Class = 1
    ) AS GoldBadges,
    CASE 
        WHEN ua.QuestionsAsked > 0 THEN (CAST(ua.AnswersProvided AS DOUBLE PRECISION) / CAST(ua.QuestionsAsked AS DOUBLE PRECISION))
        ELSE NULL 
    END AS AnswerToQuestionRatio
FROM 
    UserActivity ua
FULL OUTER JOIN 
    TagAnalysis ta ON POSITION(ta.Tags IN ua.DisplayName) > 0
WHERE 
    ua.RankByQuestions <= 100
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.QuestionsAsked,
    ua.AnswersProvided,
    ua.AvgPostScore,
    ua.EditsMade,
    ta.Tags,
    ta.PostCount,
    ta.AvgTagScore,
    ua.RankByQuestions
ORDER BY 
    ua.QuestionsAsked DESC,
    ta.PostCount DESC
LIMIT 50;