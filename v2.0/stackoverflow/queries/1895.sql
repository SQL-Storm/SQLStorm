-- {"query": "1895.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3113}
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(AVG(P.Score), 0) AS AvgPostScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        CAST(U.UpVotes AS NUMERIC) / NULLIF(U.DownVotes, 0) AS UpDownVoteRatio,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - U.CreationDate)) / 86400.0 AS DaysSinceCreation,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 5
),
PostVoteCounts AS (
    SELECT
        PostId,
        SUM(CASE WHEN VT.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN VT.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN VT.Name = 'Favorite' THEN 1 ELSE 0 END) AS FavoriteCountFromVotes
    FROM Votes V
    JOIN VoteTypes VT ON V.VoteTypeId = VT.Id
    GROUP BY PostId
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        COALESCE(P.FavoriteCount, 0) AS PostFavoriteCount,
        P.CommentCount,
        P.ClosedDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        COALESCE(PVC.UpVoteCount, 0) AS TotalUpvotesOnPost,
        COALESCE(PVC.DownVoteCount, 0) AS TotalDownvotesOnPost,
        COALESCE(PVC.FavoriteCountFromVotes, 0) AS TotalFavoriteVotesOnPost,
        COALESCE(P.Score, 0) / NULLIF(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - P.CreationDate)) / 86400.0, 0) AS ScorePerDay,
        CASE
            WHEN P.ClosedDate IS NOT NULL AND P.PostTypeId = 1 THEN 'Closed Question'
            WHEN P.AcceptedAnswerId IS NOT NULL AND P.PostTypeId = 1 THEN 'Answered Question'
            WHEN P.AnswerCount = 0 AND P.PostTypeId = 1 THEN 'Unanswered Question'
            WHEN P.PostTypeId = 2 THEN 'Answer Post'
            ELSE 'Other Post Type'
        END AS PostStatus,
        ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'), 1) AS TagCount,
        P.CreationDate AS CreationDate -- include for later filtering/grouping
    FROM Posts P
    LEFT JOIN PostVoteCounts PVC ON P.Id = PVC.PostId
    WHERE P.PostTypeId IN (1, 2)
),
PostEditDetails AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS EditDate,
        PH.UserId AS EditorUserId,
        PH.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS rn
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9)
),
RecentPostEdits AS (
    SELECT
        PED.PostId,
        MAX(PED.EditDate) AS LastEditHistoryDate,
        COUNT(*) AS TotalRevisions,
        COUNT(DISTINCT PED.EditorUserId) AS UniqueEditors,
        (SELECT U.DisplayName FROM Users U WHERE U.Id = (SELECT EditorUserId FROM PostEditDetails WHERE PostId = PED.PostId AND rn = 1)) AS LatestEditorDisplayName,
        (SELECT PHT.Name FROM PostHistoryTypes PHT WHERE PHT.Id = (SELECT PostHistoryTypeId FROM PostEditDetails WHERE PostId = PED.PostId AND rn = 1)) AS LatestEditAction
    FROM PostEditDetails PED
    WHERE PED.EditDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months'
    GROUP BY PED.PostId
),
UserBadgesSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges B
    GROUP BY B.UserId
),
HighImpactQuestionsBranch AS (
    SELECT
        PEM.PostId,
        PEM.Title,
        UAS.DisplayName AS QuestionOwner,
        UAS.Reputation AS OwnerReputation,
        PEM.PostCreationDate,
        PEM.Score AS QuestionScore,
        PEM.ViewCount,
        PEM.PostFavoriteCount,
        PEM.CommentCount,
        PEM.PostStatus,
        COALESCE(RPE.TotalRevisions, 0) AS TotalEditRevisions,
        RPE.LatestEditorDisplayName,
        RPE.LatestEditAction,
        CAST(NULL AS VARCHAR(300)) AS RelatedPostTitle,
        'HighViewFavorite' AS ImpactCategory,
        (SELECT COALESCE(SUM(Ans.Score), 0) FROM Posts Ans WHERE Ans.ParentId = PEM.PostId AND Ans.PostTypeId = 2) AS SumOfAnswerScores,
        COALESCE(UAS.UpDownVoteRatio, 0.0) AS OwnerUpDownVoteRatio,
        (SELECT AVG(SubQ.Score)
         FROM Posts SubQ
         WHERE SubQ.PostTypeId = 1
           AND SubQ.OwnerUserId IN (
               SELECT InnerU.Id
               FROM Users InnerU
               WHERE InnerU.Reputation BETWEEN UAS.Reputation - 1000 AND UAS.Reputation + 1000
           )
           AND SubQ.CreationDate < PEM.PostCreationDate
           AND SubQ.Score IS NOT NULL
        ) AS AvgSimilarRepUserQScore,
        CAST(NULL AS INTEGER) AS CountOfRelatedSpecificTags
    FROM PostEngagementMetrics PEM
    JOIN UserActivitySummary UAS ON PEM.OwnerUserId = UAS.UserId
    LEFT JOIN RecentPostEdits RPE ON PEM.PostId = RPE.PostId
    LEFT JOIN UserBadgesSummary UBS ON UAS.UserId = UBS.UserId
    WHERE PEM.PostTypeId = 1
      AND PEM.ViewCount > 50000
      AND PEM.PostFavoriteCount > 100
      AND UAS.Reputation > 20000
      AND PEM.PostStatus NOT LIKE '%Closed%'
      AND EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = UAS.UserId AND B.Class = 1)
      AND PEM.Tags IS NOT NULL
      AND LOWER(PEM.Tags) LIKE '%<sql>%'
      AND PEM.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '4 years'
    GROUP BY
        PEM.PostId, PEM.Title, UAS.DisplayName, UAS.Reputation, PEM.PostCreationDate, PEM.Score, PEM.ViewCount,
        PEM.PostFavoriteCount, PEM.CommentCount, PEM.PostStatus, RPE.TotalRevisions, RPE.LatestEditorDisplayName,
        RPE.LatestEditAction, UAS.UpDownVoteRatio
),
ActiveCommunityContributionsBranch AS (
    SELECT
        PEM.PostId,
        PEM.Title,
        UAS.DisplayName AS QuestionOwner,
        UAS.Reputation AS OwnerReputation,
        PEM.PostCreationDate,
        PEM.Score AS QuestionScore,
        PEM.ViewCount,
        PEM.PostFavoriteCount,
        PEM.CommentCount,
        PEM.PostStatus,
        COALESCE(RPE.TotalRevisions, 0) AS TotalEditRevisions,
        RPE.LatestEditorDisplayName,
        RPE.LatestEditAction,
        COALESCE(P_linked.Title, 'No Linked Title') AS RelatedPostTitle,
        'ActiveCommunity' AS ImpactCategory,
        (SELECT COALESCE(SUM(Ans.Score), 0) FROM Posts Ans WHERE Ans.ParentId = PEM.PostId AND Ans.PostTypeId = 2) AS SumOfAnswerScores,
        COALESCE(UAS.UpDownVoteRatio, 0.0) AS OwnerUpDownVoteRatio,
        CAST(NULL AS NUMERIC) AS AvgSimilarRepUserQScore,
        (SELECT COUNT(DISTINCT T_rel.TagName)
         FROM PostLinks PL_inner
         JOIN Posts P_rel ON PL_inner.RelatedPostId = P_rel.Id
         JOIN Tags T_rel ON P_rel.Tags LIKE '%<' || T_rel.TagName || '>%'
         WHERE PL_inner.PostId = PEM.PostId
           AND P_rel.Tags IS NOT NULL
           AND LOWER(P_rel.Tags) LIKE '%<database>%'
           AND T_rel.TagName IN ('sql', 'postgresql', 'mysql')
        ) AS CountOfRelatedSpecificTags
    FROM PostEngagementMetrics PEM
    JOIN UserActivitySummary UAS ON PEM.OwnerUserId = UAS.UserId
    LEFT JOIN RecentPostEdits RPE ON PEM.PostId = RPE.PostId
    LEFT JOIN PostLinks PL ON PEM.PostId = PL.PostId AND PL.LinkTypeId = 1
    LEFT JOIN Posts P_linked ON PL.RelatedPostId = P_linked.Id
    WHERE PEM.PostTypeId = 1
      AND PEM.CommentCount > 50
      AND PEM.TotalUpvotesOnPost > 200
      AND COALESCE(RPE.TotalRevisions, 0) > 10
      AND PEM.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 years'
      AND PEM.ClosedDate IS NULL
      AND PEM.OwnerUserId IS NOT NULL
      AND (UAS.ReputationRank <= 1000 OR UAS.TotalQuestions > 50)
    GROUP BY
        PEM.PostId, PEM.Title, UAS.DisplayName, UAS.Reputation, PEM.PostCreationDate, PEM.Score, PEM.ViewCount,
        PEM.PostFavoriteCount, PEM.CommentCount, PEM.PostStatus, RPE.TotalRevisions, RPE.LatestEditorDisplayName,
        RPE.LatestEditAction, P_linked.Title, UAS.UpDownVoteRatio
)
SELECT
    PostId,
    Title,
    QuestionOwner,
    OwnerReputation,
    PostCreationDate,
    QuestionScore,
    ViewCount,
    PostFavoriteCount,
    CommentCount,
    PostStatus,
    TotalEditRevisions,
    LatestEditorDisplayName,
    LatestEditAction,
    RelatedPostTitle,
    ImpactCategory,
    SumOfAnswerScores,
    OwnerUpDownVoteRatio,
    AvgSimilarRepUserQScore,
    CountOfRelatedSpecificTags
FROM HighImpactQuestionsBranch
WHERE PostId NOT IN (SELECT PostId FROM ActiveCommunityContributionsBranch)
UNION ALL
SELECT
    PostId,
    Title,
    QuestionOwner,
    OwnerReputation,
    PostCreationDate,
    QuestionScore,
    ViewCount,
    PostFavoriteCount,
    CommentCount,
    PostStatus,
    TotalEditRevisions,
    LatestEditorDisplayName,
    LatestEditAction,
    RelatedPostTitle,
    ImpactCategory,
    SumOfAnswerScores,
    OwnerUpDownVoteRatio,
    AvgSimilarRepUserQScore,
    CountOfRelatedSpecificTags
FROM ActiveCommunityContributionsBranch
ORDER BY PostCreationDate DESC, QuestionScore DESC
LIMIT 1000;