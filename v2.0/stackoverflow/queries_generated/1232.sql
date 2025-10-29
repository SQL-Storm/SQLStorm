-- {"query": "1232.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2330} 
WITH UserActivitySummary AS (
    -- Summarizes user engagement metrics including votes, post counts, and badge counts
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
        (SELECT COUNT(DISTINCT V.Id) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId = 5) AS TotalFavoritesMade -- Correlated subquery for favorites
    FROM
        Users U
    LEFT JOIN Posts Q ON U.Id = Q.OwnerUserId AND Q.PostTypeId = 1
    LEFT JOIN Posts A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2
    LEFT JOIN Posts P ON A.ParentId = P.Id -- Link answers to questions to check for accepted answers
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes, U.Location, U.AboutMe
    HAVING
        U.Reputation > 500 OR COUNT(DISTINCT B.Id) >= 5
),
QuestionPerformanceMetrics AS (
    -- Analyzes performance and activity metrics for questions
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
        P.PostTypeId = 1 -- Only questions
    GROUP BY
        P.Id, P.OwnerUserId, P.Title, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount
    HAVING
        P.ViewCount > 1000 AND P.Score > 5
),
TagAnalysis AS (
    -- Extracts and ranks tags based on their usage in high-performing questions
    SELECT
        TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(T.Tags, 2, LENGTH(T.Tags) - 2), '><'))) AS TagName,
        COUNT(T.Id) AS TaggedQuestionCount,
        SUM(T.ViewCount) AS TotalTagViews,
        AVG(T.Score) AS AvgTagScore
    FROM
        Posts T
    WHERE
        T.PostTypeId = 1 AND T.Tags IS NOT NULL
    GROUP BY
        TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(T.Tags, 2, LENGTH(T.Tags) - 2), '><')))
    HAVING
        COUNT(T.Id) > 50
),
RankedPopularTags AS (
    -- Ranks the tags from TagAnalysis
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
-- Main Query: Combine user engagement, question performance, and tag analysis
-- This query aims to find highly active users who ask complex questions that are frequently edited,
-- often involve popular tags, and have received significant attention (views, votes, comments).
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
    (CAST(QPM.ReopenedCount AS DECIMAL) / NULLIF(QPM.ClosedCount, 0)) AS ReopenRatio,
    (SELECT PH_Body.Text FROM PostHistory PH_Body WHERE PH_Body.PostId = QPM.QuestionId AND PH_Body.PostHistoryTypeId = 2 ORDER BY PH_Body.CreationDate ASC LIMIT 1) AS InitialPostBodySnippet, -- Correlated subquery for initial post body
    CASE
        WHEN QPM.ReopenedCount > 0 AND QPM.LatestReopenedDate IS NOT NULL THEN 'Reopened'
        WHEN QPM.ClosedCount > 0 AND QPM.LatestReopenedDate IS NULL THEN 'ClosedPermanently'
        ELSE 'Active'
    END AS QuestionStatusCategory,
    NTH_VALUE(UAS.DisplayName, 1) OVER (PARTITION BY EXTRACT(YEAR FROM UAS.UserCreationDate) ORDER BY UAS.Reputation DESC) AS TopRepUserInCreationYear, -- Window function
    LAG(UAS.Reputation, 1, 0) OVER (PARTITION BY UAS.UserLocation ORDER BY UAS.EngagementScore DESC) AS PrevUserReputationInLocation
FROM
    UserActivitySummary UAS
INNER JOIN QuestionPerformanceMetrics QPM ON UAS.UserId = QPM.OwnerUserId
LEFT JOIN Posts P_Tags ON QPM.QuestionId = P_Tags.Id -- To link questions to tags
LEFT JOIN LATERAL (
    -- Lateral join to find the most popular tag for each question
    SELECT
        TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P_Tags.Tags, 2, LENGTH(P_Tags.Tags) - 2), '><'))) AS TagName_Raw
) AS QuestionTags ON TRUE
LEFT JOIN RankedPopularTags RPT ON QuestionTags.TagName_Raw = RPT.TagName
WHERE
    UAS.EngagementScore > 1000
    AND QPM.QuestionCreationDate BETWEEN '2015-01-01' AND '2020-12-31'
    AND QPM.EditCount >= 3
    AND (QPM.ClosedCount > 0 OR QPM.ReopenedCount > 0)
    AND QPM.AverageAnswerScore IS NOT NULL AND QPM.AverageAnswerScore > 0
    AND (QPM.QuestionScore / NULLIF(QPM.ViewCount, 0)::DECIMAL * 100) > 0.5 -- Score to View Ratio percentage
    AND (RPT.TagPopularityRank <= 10 OR RPT.TagName IS NULL) -- Prioritize questions with top 10 tags or those without a major tag
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.UserLocation, UAS.AboutMeCategory, UAS.EngagementScore,
    QPM.QuestionId, QPM.Title, QPM.QuestionCreationDate, QPM.QuestionScore, QPM.ViewCount,
    QPM.DeclaredAnswerCount, QPM.ActualCommentCount, QPM.EditCount, QPM.ClosedCount, QPM.ReopenedCount,
    QPM.AverageAnswerScore, RPT.TagName, RPT.TagPopularityRank, QPM.FirstClosedDate, QPM.LatestReopenedDate,
    UAS.UserCreationDate
HAVING
    COUNT(DISTINCT RPT.TagName) <= 2 OR (MAX(RPT.TagPopularityRank) IS NULL AND COUNT(DISTINCT RPT.TagName) = 0)
ORDER BY
    UAS.EngagementScore DESC, QPM.QuestionImpactScore DESC
LIMIT 500;