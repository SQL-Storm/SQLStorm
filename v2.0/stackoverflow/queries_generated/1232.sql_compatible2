WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT Q.Id) AS QuestionsAsked,
        COUNT(DISTINCT A.Id) AS AnswersGiven,
        SUM(CASE WHEN A.Id IS NOT NULL AND A.Id = P.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        COUNT(DISTINCT B.Id) AS BadgesCount,
        (CAST(U.UpVotes AS BIGINT) * 5 + U.Reputation + COUNT(DISTINCT Q.Id) * 10 + COUNT(DISTINCT A.Id) * 7 + COUNT(DISTINCT B.Id) * 3) AS EngagementScore,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        CASE
            WHEN U.AboutMe LIKE '%developer%' OR U.AboutMe LIKE '%coder%' THEN 'Developer'
            WHEN U.AboutMe LIKE '%student%' THEN 'Student'
            ELSE 'Other/Undefined'
        END AS AboutMeCategory,
        (SELECT COUNT(DISTINCT V.Id) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId = 5) AS TotalFavoritesMade
    FROM
        Users U
    LEFT JOIN Posts Q ON U.Id = Q.OwnerUserId AND Q.PostTypeId = 1
    LEFT JOIN Posts A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2
    LEFT JOIN Posts P ON A.ParentId = P.Id
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes, U.Location, U.AboutMe
    HAVING
        U.Reputation > 500 OR COUNT(DISTINCT B.Id) >= 5
),
QuestionPerformanceMetrics AS (
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId,
        P.Title,
        P.CreationDate AS QuestionCreationDate,
        P.Score AS QuestionScore,
        P.ViewCount,
        P.AnswerCount AS DeclaredAnswerCount,
        P.CommentCount AS DeclaredCommentCount,
        COUNT(DISTINCT PH.Id) AS HistoryEntryCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        MAX(PH.CreationDate) AS LastHistoryActivity,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenedCount,
        AVG(Ans.Score) AS AverageAnswerScore,
        COUNT(DISTINCT C.Id) AS ActualCommentCount,
        (SELECT MIN(PH_Closed.CreationDate) FROM PostHistory PH_Closed WHERE PH_Closed.PostId = P.Id AND PH_Closed.PostHistoryTypeId = 10) AS FirstClosedDate,
        (SELECT MAX(PH_Reopened.CreationDate) FROM PostHistory PH_Reopened WHERE PH_Reopened.PostId = P.Id AND PH_Reopened.PostHistoryTypeId = 11) AS LatestReopenedDate
    FROM
        Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Posts Ans ON P.Id = Ans.ParentId AND Ans.PostTypeId = 2
    WHERE
        P.PostTypeId = 1
    GROUP BY
        P.Id, P.OwnerUserId, P.Title, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount
    HAVING
        P.ViewCount > 1000 AND P.Score > 5
),
TagAnalysis AS (
    SELECT
        TRIM(tag) AS TagName,
        COUNT(t.Id) AS TaggedQuestionCount,
        SUM(t.ViewCount) AS TotalTagViews,
        AVG(t.Score) AS AvgTagScore
    FROM
        Posts t,
        LATERAL (
           SELECT regexp_split_to_table(substring(t.tags FROM 2 FOR char_length(t.tags)-2), '><') AS tag
        ) s
    WHERE
        t.PostTypeId = 1 AND t.Tags IS NOT NULL
    GROUP BY
        TRIM(tag)
    HAVING
        COUNT(t.Id) > 50
),
RankedPopularTags AS (
    SELECT
        TagName,
        TaggedQuestionCount,
        TotalTagViews,
        AvgTagScore,
        DENSE_RANK() OVER (ORDER BY TaggedQuestionCount DESC, TotalTagViews DESC) AS TagPopularityRank
    FROM
        TagAnalysis
    WHERE
        AvgTagScore > 2.0
)
SELECT
    UAS.UserId,
    UAS.DisplayName AS UserDisplayName,
    UAS.Reputation,
    UAS.UserLocation,
    UAS.AboutMeCategory,
    UAS.EngagementScore,
    QPM.QuestionId,
    QPM.Title AS QuestionTitle,
    QPM.QuestionCreationDate,
    QPM.QuestionScore,
    QPM.ViewCount,
    QPM.DeclaredAnswerCount,
    QPM.ActualCommentCount,
    QPM.EditCount,
    QPM.ClosedCount,
    QPM.ReopenedCount,
    QPM.AverageAnswerScore,
    COALESCE(RPT.TagName, 'NoMajorTag') AS TopRelatedTag,
    RPT.TagPopularityRank,
    (QPM.ViewCount * QPM.QuestionScore) AS QuestionImpactScore,
    (CAST(QPM.ReopenedCount AS NUMERIC) / NULLIF(QPM.ClosedCount, 0)) AS ReopenRatio,
    (SELECT PH_Body.Text FROM PostHistory PH_Body WHERE PH_Body.PostId = QPM.QuestionId AND PH_Body.PostHistoryTypeId = 2 ORDER BY PH_Body.CreationDate ASC LIMIT 1) AS InitialPostBodySnippet,
    CASE
        WHEN QPM.ReopenedCount > 0 AND QPM.LatestReopenedDate IS NOT NULL THEN 'Reopened'
        WHEN QPM.ClosedCount > 0 AND QPM.LatestReopenedDate IS NULL THEN 'ClosedPermanently'
        ELSE 'Active'
    END AS QuestionStatusCategory,
    NTH_VALUE(UAS.DisplayName, 1) OVER (PARTITION BY EXTRACT(YEAR FROM UAS.UserCreationDate) ORDER BY UAS.Reputation DESC) AS TopRepUserInCreationYear,
    LAG(UAS.Reputation, 1, 0) OVER (PARTITION BY UAS.UserLocation ORDER BY UAS.EngagementScore DESC) AS PrevUserReputationInLocation
FROM
    UserActivitySummary UAS
INNER JOIN QuestionPerformanceMetrics QPM ON UAS.UserId = QPM.OwnerUserId
LEFT JOIN Posts P_Tags ON QPM.QuestionId = P_Tags.Id
LEFT JOIN LATERAL (
    SELECT regexp_split_to_table(substring(P_Tags.tags FROM 2 FOR char_length(P_Tags.tags)-2), '><') AS TagName_Raw
) AS QuestionTags ON TRUE
LEFT JOIN RankedPopularTags RPT ON QuestionTags.TagName_Raw = RPT.TagName
WHERE
    UAS.EngagementScore > 1000
    AND QPM.QuestionCreationDate BETWEEN DATE '2015-01-01' AND DATE '2020-12-31'
    AND QPM.EditCount >= 3
    AND (QPM.ClosedCount > 0 OR QPM.ReopenedCount > 0)
    AND QPM.AverageAnswerScore IS NOT NULL AND QPM.AverageAnswerScore > 0
    AND ((QPM.QuestionScore / NULLIF(QPM.ViewCount, 0)) * 100) > 0.5
    AND (RPT.TagPopularityRank <= 10 OR RPT.TagName IS NULL)
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.UserLocation, UAS.AboutMeCategory, UAS.EngagementScore,
    QPM.QuestionId, QPM.Title, QPM.QuestionCreationDate, QPM.QuestionScore, QPM.ViewCount,
    QPM.DeclaredAnswerCount, QPM.ActualCommentCount, QPM.EditCount, QPM.ClosedCount, QPM.ReopenedCount,
    QPM.AverageAnswerScore, RPT.TagName, RPT.TagPopularityRank, QPM.FirstClosedDate, QPM.LatestReopenedDate,
    UAS.UserCreationDate, UAS.EngagementScore, UAS.UserLocation
HAVING
    COUNT(DISTINCT RPT.TagName) <= 2 OR (MAX(RPT.TagPopularityRank) IS NULL AND COUNT(DISTINCT RPT.TagName) = 0)
ORDER BY
    UAS.EngagementScore DESC, QuestionImpactScore DESC
LIMIT 500;