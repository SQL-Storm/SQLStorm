WITH TopTags AS (
    SELECT
        Tags.TagName,
        COUNT(P.Id) AS QuestionCount,
        SUM(P.ViewCount) AS TotalViews,
        SUM(P.Score) AS TotalScore,
        SUM(P.AnswerCount) AS TotalAnswers
    FROM
        Tags
    JOIN Posts P ON P.Tags LIKE '%' || '<' || Tags.TagName || '>' || '%'
    WHERE
        P.PostTypeId = 1
    GROUP BY
        Tags.TagName
    ORDER BY
        TotalViews DESC
    LIMIT 10
), MostActiveUsers AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        SUM(P.ViewCount) AS TotalViews
    FROM
        Posts P
    WHERE
        P.PostTypeId IN (1, 2)
    GROUP BY
        P.OwnerUserId
    ORDER BY
        TotalScore DESC
    LIMIT 10
), UserActivity AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, NULL) AS DisplayName
    FROM
        Users U
)
SELECT
    U.UserId,
    U.DisplayName,
    COALESCE(A.TotalScore, 0) AS TotalScore,
    COALESCE(A.TotalViews, 0) AS TotalViews
FROM
    UserActivity U
LEFT JOIN (
    SELECT
        OwnerUserId AS UserId,
        SUM(Score) AS TotalScore,
        SUM(ViewCount) AS TotalViews
    FROM
        Posts
    WHERE
        PostTypeId IN (1, 2)
    GROUP BY
        OwnerUserId
) A ON A.UserId = U.UserId
ORDER BY
    TotalScore DESC
LIMIT 100;