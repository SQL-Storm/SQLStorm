-- {"query": "1530.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2523} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestions,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswers,
        COALESCE(COUNT(DISTINCT P.Id), 0) AS TotalPosts,
        COALESCE(AVG(P.Score), 0.0) AS AvgPostScore,
        COALESCE(SUM(V.BountyAmount) FILTER (WHERE V.VoteTypeId = 8), 0) AS TotalBountyGiven, -- VoteType 8 = BountyStart
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        RANK() OVER (ORDER BY U.Reputation DESC, U.LastAccessDate DESC) AS ReputationRank,
        LAG(U.Reputation, 1, 0) OVER (ORDER BY U.Reputation DESC) AS PrevUserReputation,
        U.AboutMe,
        U.WebsiteUrl,
        U.Location
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.AboutMe, U.WebsiteUrl, U.Location
    HAVING U.Reputation > 500 AND COUNT(DISTINCT P.Id) > 10
),
PostDetails AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.AcceptedAnswerId,
        LENGTH(COALESCE(P.Body, '')) AS BodyLength,
        COALESCE(LENGTH(P.Tags) - LENGTH(REPLACE(P.Tags, '><', '')) + 1, 0) AS TagCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived, -- VoteType 2 = UpMod
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived, -- VoteType 3 = DownMod
        AVG(CM.Score) AS AvgCommentScorePerPost,
        DENSE_RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS PostTypeScoreRank,
        (SELECT MAX(PH_INNER.CreationDate) FROM PostHistory PH_INNER WHERE PH_INNER.PostId = P.Id AND PH_INNER.PostHistoryTypeId IN (4, 5, 6)) AS LastEditDateHistory
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN Comments CM ON P.Id = CM.PostId
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.AcceptedAnswerId, P.Body, P.Tags
),
PostHistoryAggregates AS (
    SELECT
        PH.PostId,
        COUNT(DISTINCT PH.RevisionGUID) AS UniqueEditRevisions,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 'Closed' ELSE 'Open' END) AS CloseStatusIndicator,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 11) THEN 1 ELSE 0 END) AS CloseReopenEvents,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN CRT.Name ELSE NULL END) AS LastCloseReason,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (10,12)) AS LastClosureDeletionDate
    FROM PostHistory PH
    LEFT JOIN CloseReasonTypes CRT ON PH.PostHistoryTypeId = 10 AND CRT.Id = CAST(PH.Comment AS SMALLINT) -- Only join for close events
    WHERE PH.PostHistoryTypeId IN (1,2,3,4,5,6,10,11,12,13) -- Initial, Edit, Close, Reopen, Delete, Undelete
    GROUP BY PH.PostId
),
BadgeMetrics AS (
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges,
        STRING_AGG(DISTINCT B.Name, ', ') FILTER (WHERE B.Class = 1) AS GoldBadgeNames
    FROM Badges B
    GROUP BY B.UserId
),
TopQuestionTags AS (
    SELECT
        TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))) AS TagName,
        COUNT(P.Id) AS QuestionCount
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL
    GROUP BY 1
    HAVING COUNT(P.Id) > 1000
    ORDER BY QuestionCount DESC
    LIMIT 5
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.ReputationRank,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.TotalPosts,
    PD.PostId,
    PD.PostTypeScoreRank,
    PD.PostCreationDate,
    PD.PostScore,
    PD.ViewCount,
    PD.BodyLength,
    PD.TagCount,
    PD.UpvotesReceived,
    PD.DownvotesReceived,
    PD.AvgCommentScorePerPost,
    COALESCE(B.GoldBadges, 0) AS GoldBadges,
    COALESCE(B.SilverBadges, 0) AS SilverBadges,
    COALESCE(B.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(B.TotalBadges, 0) AS TotalBadges,
    B.GoldBadgeNames,
    PHA.UniqueEditRevisions,
    PHA.CloseStatusIndicator,
    PHA.CloseReopenEvents,
    PHA.LastCloseReason,
    COALESCE(EXTRACT(EPOCH FROM (PD.LastEditDateHistory - PD.PostCreationDate)) / 3600.0, 0.0) AS HoursToLastEdit,
    COALESCE(EXTRACT(EPOCH FROM (PHA.LastClosureDeletionDate - PD.PostCreationDate)) / 86400.0, 0.0) AS DaysToClosureOrDeletion,
    CASE
        WHEN UE.Reputation >= 10000 AND COALESCE(B.GoldBadges, 0) >= 5 AND PD.PostTypeScoreRank = 1 THEN 'Legendary Contributor'
        WHEN UE.TotalQuestions >= 50 AND UE.AvgPostScore >= 5 AND PD.TagCount >= 3 THEN 'Proactive Questioner'
        WHEN UE.TotalAnswers >= 100 AND PD.UpvotesReceived > 200 THEN 'Top Answerer'
        WHEN UE.Location LIKE '%United States%' AND UE.TotalPosts > 50 THEN 'US Based Active User'
        WHEN UE.WebsiteUrl IS NOT NULL AND UE.WebsiteUrl LIKE '%github.com%' THEN 'Dev Community Integrator'
        WHEN UE.AboutMe LIKE '%software%' OR UE.AboutMe LIKE '%developer%' THEN 'Self-Described Developer'
        ELSE 'General Contributor'
    END AS UserProfileCategory,
    (
        SELECT COUNT(DISTINCT C.Id)
        FROM Comments C
        WHERE C.UserId = UE.UserId
        AND C.CreationDate > UE.LastAccessDate - INTERVAL '30 days'
        AND C.Score > 0
    ) AS RecentPositiveCommentsByUser, -- Correlated subquery
    NOT EXISTS (
        SELECT 1
        FROM Posts MissingAnswer
        WHERE MissingAnswer.OwnerUserId = UE.UserId
        AND MissingAnswer.PostTypeId = 1
        AND MissingAnswer.AcceptedAnswerId IS NULL
        AND MissingAnswer.CreationDate < NOW() - INTERVAL '1 year'
    ) AS HasAllOldQuestionsReceivedAcceptedAnswers, -- Correlated subquery with NOT EXISTS
    (SELECT T.TagName FROM TopQuestionTags T ORDER BY T.QuestionCount DESC LIMIT 1) AS MostPopularTagOverall, -- Scalar subquery
    'QueryGenerated_' || REPLACE(CAST(NOW() AS VARCHAR), ' ', '_') AS QueryRunIdentifier
FROM UserEngagement UE
LEFT JOIN PostDetails PD ON UE.UserId = PD.OwnerUserId
LEFT JOIN BadgeMetrics B ON UE.UserId = B.UserId
LEFT JOIN PostHistoryAggregates PHA ON PD.PostId = PHA.PostId
WHERE
    PD.PostTypeScoreRank <= 100 -- Focus on relatively highly-ranked posts
    AND PD.PostScore >= 5
    AND PD.PostTypeId IN (1, 2)
    AND (PD.ClosedDate IS NULL OR PD.ClosedDate > UE.LastAccessDate - INTERVAL '2 years') -- Not too old closed posts
    AND (
        (UE.TotalQuestions >= 10 AND COALESCE(B.GoldBadges, 0) > 0)
        OR (UE.TotalAnswers >= 20 AND PD.UpvotesReceived >= 20)
    )
    AND UE.LastAccessDate > UE.UserCreationDate + INTERVAL '180 days' -- User active for at least 6 months
    AND UE.AboutMe IS NOT NULL AND LENGTH(UE.AboutMe) > 100
    AND NOT EXISTS (
        SELECT 1
        FROM Posts P_sub
        WHERE P_sub.OwnerUserId = UE.UserId
        AND P_sub.ViewCount < 50
        AND P_sub.CreationDate < UE.LastAccessDate - INTERVAL '3 year'
        AND P_sub.PostTypeId = 1
    ) -- Another correlated subquery to exclude users with very old, low-view questions
ORDER BY
    UE.ReputationRank ASC,
    PD.PostScore DESC,
    PHA.UniqueEditRevisions DESC NULLS LAST,
    UE.LastAccessDate DESC
LIMIT 2000;
