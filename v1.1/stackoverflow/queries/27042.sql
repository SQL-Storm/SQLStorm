WITH ActiveUsers AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.DisplayName,
        COUNT(P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        MAX(P.CreationDate) AS LastPostDate,
        RANK() OVER (ORDER BY SUM(P.Score) DESC) AS ReputationRank
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    WHERE
        U.Reputation > 1000
        AND P.PostTypeId IN (1, 2)
        AND P.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    GROUP BY
        U.Id, U.Reputation, U.DisplayName
),
PopularTags AS (
    SELECT
        T.Id AS TagId,
        T.TagName,
        T.Count,
        COUNT(PT.Id) AS QuestionCount,
        AVG(P.Score) AS AvgScore,
        STRING_AGG(P.Title, ' ') AS TaggedPosts
    FROM
        Tags T
    LEFT JOIN
        Posts P ON T.Id = P.Id
    LEFT JOIN
        Posts PT ON POSITION(CONCAT('<', T.TagName, '>') IN PT.Tags) > 0
    WHERE
        T.Count > 1000
        AND P.PostTypeId = 1
    GROUP BY
        T.Id, T.TagName, T.Count
),
RecentActivity AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.Score,
        PH.PostHistoryTypeId,
        PH.UserId AS EditorId,
        U.DisplayName AS EditorName,
        PH.CreationDate AS EditDate,
        LAG(PH.CreationDate, 1) OVER (PARTITION BY P.Id ORDER BY PH.CreationDate) AS PreviousEditDate,
        LAG(U.DisplayName, 1) OVER (PARTITION BY P.Id ORDER BY PH.CreationDate) AS LastEditorName,
        CASE
            WHEN P.ParentId IS NULL THEN 5
            WHEN PH.PostHistoryTypeId = 10 THEN 2
            ELSE 3
        END AS PriorityScore,
        P.Score + PH.Id AS ModScore
    FROM
        Posts P
    JOIN
        PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN
        Users U ON PH.UserId = U.Id
    WHERE
        PH.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 month')
        AND PH.PostHistoryTypeId IN (10, 14, 15)
),
HighBountyPosts AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        P.Score,
        V.BountyAmount,
        U.DisplayName AS BountyUserName,
        V.CreationDate AS BountyDate,
        DENSE_RANK() OVER (PARTITION BY P.Id ORDER BY V.BountyAmount DESC) AS BountyRank
    FROM
        Votes V
    JOIN
        Posts P ON V.PostId = P.Id
    LEFT JOIN
        Users U ON V.UserId = U.Id
    WHERE
        V.VoteTypeId = 8
        AND V.BountyAmount > 50
)
SELECT
    PA.TagId,
    PT.Title AS PostTitle,
    PA.TagName,
    PA.QuestionCount,
    PA.AvgScore,
    STRING_AGG(DISTINCT PT.Title, ',') AS listOfQuestions,
    RA.PostId,
    PA.QuestionCount AS TagQuestionCount,
    RA.EditDate,
    AOP.TotalScore,
    AvHor.TagName AS AvHorTagName,
    OPP.BountyUserName,
    AU.UserId,
    AU.PostCount,
    RA.PriorityScore,
    RA.ModScore
FROM
    ActiveUsers AU
JOIN
    RecentActivity RA ON AU.UserId = RA.EditorId
LEFT JOIN
    Posts PT ON AU.UserId = PT.OwnerUserId
LEFT JOIN
    PopularTags PA ON (
        PT.Tags IS NOT NULL
        AND POSITION(CONCAT('<', PA.TagName, '>') IN PT.Tags) > 0
    )
LEFT JOIN
    Votes VTE ON RA.PostId = VTE.PostId
LEFT JOIN
    PostLinks PLO ON PLO.PostId = PA.TagId
LEFT JOIN
    HighBountyPosts OPP ON VTE.PostId = OPP.PostId
LEFT JOIN
    ActiveUsers AOP ON RA.PostId = AOP.UserId
LEFT JOIN
    PopularTags AvHor ON AvHor.TagId = PA.TagId
GROUP BY
    PA.TagId,
    PT.Title,
    PA.TagName,
    PA.QuestionCount,
    PA.AvgScore,
    RA.PostId,
    RA.EditDate,
    AOP.TotalScore,
    AvHor.TagName,
    OPP.BountyUserName,
    AU.UserId,
    AU.PostCount,
    RA.PriorityScore,
    RA.ModScore
ORDER BY
    RA.EditDate DESC,
    AU.PostCount DESC,
    RA.PriorityScore,
    RA.ModScore
LIMIT 100;