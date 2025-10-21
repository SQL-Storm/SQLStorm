WITH UserActivity AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersGiven,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS AnswerScore,
        MAX(P.CreationDate) AS LastActivityDate,
        ROW_NUMBER() OVER (ORDER BY (SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) + MAX(U.Reputation)) DESC) AS Rank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        P.CreationDate >= (DATE_TRUNC('month', CAST('2024-10-01' AS DATE)) - INTERVAL '6 months')
    GROUP BY 
        U.Id, U.DisplayName
),
TopEditors AS (
    SELECT 
        UserId,
        COUNT(*) AS EditsMade
    FROM 
        PostHistory
    WHERE 
        PostHistoryTypeId IN (4, 5, 6)
        AND CreationDate >= (DATE_TRUNC('month', CAST('2024-10-01' AS DATE)) - INTERVAL '6 months')
    GROUP BY 
        UserId
),
BadgeHolders AS (
    SELECT 
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        UserId
)
SELECT 
    UA.UserId,
    UA.DisplayName,
    COALESCE(UA.QuestionsAsked, 0) AS QuestionsAsked,
    COALESCE(UA.AnswersGiven, 0) AS AnswersGiven,
    COALESCE(UA.QuestionScore, 0) + COALESCE(UA.AnswerScore, 0) AS TotalScore,
    COALESCE(TE.EditsMade, 0) AS EditsMade,
    BH.GoldBadges,
    BH.SilverBadges,
    BH.BronzeBadges,
    ROW_NUMBER() OVER (
        ORDER BY 
            COALESCE(UA.QuestionScore, 0) + COALESCE(UA.AnswerScore, 0) DESC,
            COALESCE(TE.EditsMade, 0) DESC
    ) AS PerformanceRank
FROM 
    UserActivity UA
LEFT JOIN 
    TopEditors TE ON UA.UserId = TE.UserId
LEFT JOIN 
    BadgeHolders BH ON UA.UserId = BH.UserId
WHERE 
    UA.Rank <= 100
ORDER BY 
    PerformanceRank;