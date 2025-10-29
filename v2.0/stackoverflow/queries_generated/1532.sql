-- {"query": "1532.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2762} 
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestionsPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswersPosted,
        COALESCE(COUNT(DISTINCT P.Id), 0) AS TotalPostsCreated,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        MAX(U.LastAccessDate) AS LastRecordedActivityDate,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) AS ReputationRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS InitialScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS OriginalCommentCount,
        P.FavoriteCount,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        LENGTH(P.Body) AS BodyLength,
        NULLIF(LENGTH(P.Title), 0) AS TitleLength, -- NULLIF example
        CASE
            WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
            THEN string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')
            ELSE NULL
        END AS PostTagsArray,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsOnPost,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 WHEN V.VoteTypeId = 3 THEN -1 ELSE 0 END), 0) AS NetVotesReceived,
        AVG(C.Score) FILTER (WHERE C.Id IS NOT NULL) AS AverageCommentScoreOnPost, -- Conditional aggregation
        MAX(C.CreationDate) FILTER (WHERE C.Id IS NOT NULL) AS LastCommentDate,
        NTILE(5) OVER (PARTITION BY P.PostTypeId ORDER BY P.ViewCount DESC) AS ViewCountQuintile,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS UserPostSequence
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2,3) -- UpMod, DownMod
    GROUP BY P.Id, P.PostTypeId, PT.Name, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount,
             P.AnswerCount, P.CommentCount, P.FavoriteCount, P.LastEditDate, P.LastActivityDate,
             P.ClosedDate, P.Body, P.Title, P.Tags
),
PostHistoryDetails AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditRevisions,
        MAX(PH.CreationDate) AS LastHistoryUpdate,
        MIN(PH.CreationDate) AS FirstHistoryUpdate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN (SELECT CR.Name FROM CloseReasonTypes CR WHERE CR.Id = CAST(PH.Comment AS SMALLINT)) ELSE NULL END) AS ActualCloseReasonName, -- Correlated subquery
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousHistoryEntryDate,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 12) THEN 1 ELSE 0 END) AS TotalClosedDeletedEvents,
        COALESCE(MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END), 0) AS WasClosed,
        COALESCE(MAX(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 ELSE 0 END), 0) AS WasDeleted
    FROM PostHistory PH
    GROUP BY PH.PostId
),
DailyEngagementSnapshot AS (
    SELECT
        DATE_TRUNC('day', P.CreationDate) AS SnapshotDate,
        P.PostTypeId,
        COUNT(P.Id) AS PostsCreatedDaily,
        SUM(P.Score) AS TotalDailyScore,
        AVG(P.ViewCount) FILTER (WHERE P.ViewCount IS NOT NULL) AS AvgDailyViewCount,
        SUM(COALESCE(P.AnswerCount, 0)) AS TotalDailyAnswersOnQuestions,
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY COUNT(P.Id) DESC) AS DailyPostCreationRank
    FROM Posts P
    WHERE P.CreationDate >= NOW() - INTERVAL '2 year' -- Filter for recency
    GROUP BY DATE_TRUNC('day', P.CreationDate), P.PostTypeId
    HAVING COUNT(P.Id) > 10 -- Only consider active days
),
RelevantLinkedPosts AS (
    SELECT
        PL.PostId,
        COUNT(DISTINCT PL.RelatedPostId) AS LinkedRelatedPostsCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinksCount,
        MAX(RLP.Score) AS MaxRelatedPostScore,
        AVG(RLP.Score) AS AvgRelatedPostScore
    FROM PostLinks PL
    JOIN Posts RLP ON PL.RelatedPostId = RLP.Id
    WHERE PL.CreationDate > NOW() - INTERVAL '3 months'
    GROUP BY PL.PostId
),
TopTagsSummary AS (
    SELECT
        UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS TagName,
        COUNT(P.Id) AS TaggedPostsCount,
        SUM(P.ViewCount) AS TotalTagViews,
        AVG(P.Score) AS AvgTagScore,
        SUM(P.AnswerCount) AS TotalAnswersInTag,
        DENSE_RANK() OVER (ORDER BY COUNT(P.Id) DESC, SUM(P.ViewCount) DESC) AS TagPopularityRank
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    GROUP BY TagName
    HAVING COUNT(P.Id) > 500
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalPostsCreated,
    UAS.TotalQuestionsPosted,
    UAS.TotalAnswersPosted,
    UAS.GoldBadges,
    UAS.SilverBadges,
    UAS.BronzeBadges,
    UAS.ReputationRank,
    PEG.PostId,
    PEG.PostTypeName,
    PEG.PostCreationDate,
    PEG.InitialScore,
    PEG.NetVotesReceived,
    PEG.TotalCommentsOnPost,
    PEG.BodyLength,
    PEG.TitleLength,
    PEG.FavoriteCount,
    PEG.AverageCommentScoreOnPost,
    PEG.ViewCountQuintile,
    PEG.UserPostSequence,
    PHD.TotalEditRevisions,
    PHD.ActualCloseReasonName,
    PHD.WasClosed,
    PHD.WasDeleted,
    AGE(NOW(), PHD.LastHistoryUpdate) AS TimeSinceLastHistoryUpdate, -- Date/Time calculation
    EXTRACT(HOUR FROM (PEG.LastCommentDate - PEG.PostCreationDate)) AS HoursUntilFirstComment, -- More date calculation
    DPA.SnapshotDate AS DailyActivityDate,
    DPA.PostsCreatedDaily,
    DPA.AvgDailyViewCount,
    RLP.LinkedRelatedPostsCount,
    RLP.DuplicateLinksCount,
    RLP.MaxRelatedPostScore,
    TTS.TagName AS TopRelevantTag,
    TTS.TaggedPostsCount AS TopTagPostCount,
    TTS.TagPopularityRank,
    (UAS.Reputation * 0.1 + UAS.TotalPostsCreated * 0.5 + UAS.GoldBadges * 10 + UAS.SilverBadges * 5 + UAS.BronzeBadges) AS UserActivityWeightedScore, -- Complicated calculation
    COALESCE(NULLIF(PEG.ViewCount, 0) / NULLIF(PEG.TotalCommentsOnPost, 0), 0.0) AS ViewToCommentRatio, -- NULLIF and division
    CASE
        WHEN UAS.Reputation > 50000 AND UAS.GoldBadges >= 10 AND PEG.NetVotesReceived > 100 THEN 'Legendary Contributor'
        WHEN UAS.Reputation > 10000 AND UAS.TotalPostsCreated > 100 AND PEG.PostTypeName = 'Question' AND PEG.NetVotesReceived > 50 THEN 'High-Impact Questioner'
        WHEN UAS.Reputation > 5000 AND PEG.TotalCommentsOnPost > 20 THEN 'Engaged Commenter'
        WHEN UAS.Reputation IS NULL OR UAS.Reputation <= 100 OR UAS.TotalPostsCreated < 5 THEN 'Newcomer/Lurker'
        ELSE 'Regular Participant'
    END AS UserRoleClassification -- Complex CASE expression
FROM UserActivitySummary UAS
LEFT JOIN PostEngagementMetrics PEG ON UAS.UserId = PEG.OwnerUserId
LEFT JOIN PostHistoryDetails PHD ON PEG.PostId = PHD.PostId
LEFT JOIN DailyEngagementSnapshot DPA ON DATE_TRUNC('day', PEG.PostCreationDate) = DPA.SnapshotDate AND PEG.PostTypeId = DPA.PostTypeId
LEFT JOIN RelevantLinkedPosts RLP ON PEG.PostId = RLP.PostId
LEFT JOIN TopTagsSummary TTS ON TTS.TagName = ANY(PEG.PostTagsArray) -- Array comparison for tags
WHERE
    UAS.Reputation >= 1000
    AND UAS.LastRecordedActivityDate >= NOW() - INTERVAL '6 months'
    AND PEG.PostTypeId IS NOT NULL
    AND (PEG.BodyLength > 100 OR PEG.PostTypeName = 'Answer') -- Conditional predicate
    AND NOT (PHD.WasClosed = 1 AND PHD.WasDeleted = 1) -- NOT condition with boolean logic
    AND (PEG.AverageCommentScoreOnPost IS NULL OR PEG.AverageCommentScoreOnPost > -2) -- NULL logic
    AND PEG.ViewCount > 50
ORDER BY
    UAS.Reputation DESC,
    UserActivityWeightedScore DESC,
    PEG.NetVotesReceived DESC NULLS LAST, -- NULLS LAST
    PHD.LastHistoryUpdate DESC
LIMIT 5000;