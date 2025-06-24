
WITH UserPostStats AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(P.Id) AS PostCount,
        SUM(COALESCE(P.Score, 0)) AS TotalScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalViews,
        SUM(COALESCE(P.AnswerCount, 0)) AS TotalAnswers,
        SUM(COALESCE(P.CommentCount, 0)) AS TotalComments
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    GROUP BY U.Id, U.DisplayName
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        PostCount,
        TotalScore,
        TotalViews,
        TotalAnswers,
        TotalComments,
        @ScoreRank := @ScoreRank + 1 AS ScoreRank,
        @ViewRank := @ViewRank + 1 AS ViewRank
    FROM UserPostStats, (SELECT @ScoreRank := 0, @ViewRank := 0) AS vars
    ORDER BY TotalScore DESC, TotalViews DESC
)
SELECT 
    UserId,
    DisplayName,
    PostCount,
    TotalScore,
    TotalViews,
    TotalAnswers,
    TotalComments,
    ScoreRank,
    ViewRank
FROM TopUsers
WHERE ScoreRank <= 10 OR ViewRank <= 10
ORDER BY ScoreRank, ViewRank;
