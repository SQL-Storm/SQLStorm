WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsCreated,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount,
        (
            SELECT AVG(Ans.Score)
            FROM Posts AS Ans
            WHERE Ans.OwnerUserId = U.Id
              AND Ans.PostTypeId = 2
              AND Ans.ParentId IN (SELECT Qus.Id FROM Posts AS Qus WHERE Qus.PostTypeId = 1 AND Qus.FavoriteCount > 100)
        ) AS AvgAnswerScoreToFavoredQuestions
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
),
PostDetailedMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.LastActivityDate,
        P.ClosedDate,
        P.Title AS PostTitle,
        P.Tags,
        COALESCE(P.OwnerDisplayName, U.DisplayName, 'Community') AS ActualPostOwnerDisplayName,
        COUNT(DISTINCT PH.Id) AS PostHistoryEntryCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditRevisions,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosedEventRecorded,
        MAX(PH.CreationDate) AS LastHistoryEventDate,
        CAST(EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 86400 AS INTEGER) AS PostAgeInDays,
        TRIM(BOTH '>' FROM SUBSTR(P.Tags, POSITION('<' IN P.Tags) + 1, POSITION('>' IN P.Tags) - POSITION('<' IN P.Tags) - 1)) AS PrimaryTag,
        EXISTS (
            SELECT 1
            FROM Posts AS A
            JOIN Votes AS V ON A.Id = V.PostId
            WHERE A.ParentId = P.Id
              AND A.PostTypeId = 2
              AND V.VoteTypeId IN (8, 9)
        ) AS HasBountiedAnswer,
        COALESCE(SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END), 0) AS LinkedPostCount,
        COALESCE(SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END), 0) AS DuplicateOfCount
    FROM Posts AS P
    LEFT JOIN Users AS U ON P.OwnerUserId = U.Id
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN PostLinks AS PL ON P.Id = PL.PostId
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount,
             P.OwnerUserId, P.LastActivityDate, P.ClosedDate, P.Title, P.Tags, U.DisplayName, P.OwnerDisplayName
),
TagPerformance AS (
    SELECT
        T.TagName,
        T.Count AS TotalTagPosts,
        T.IsModeratorOnly,
        T.IsRequired,
        P_Excerpt.Title AS ExcerptPostTitle,
        P_Wiki.Title AS WikiPostTitle,
        RANK() OVER (ORDER BY T.Count DESC) AS TagPopularityRank,
        (
            SELECT AVG(P_Tag.Score)
            FROM Posts AS P_Tag
            WHERE P_Tag.Tags LIKE ('%<' || T.TagName || '>%')
              AND P_Tag.CommentCount > 0
        ) AS AvgScoreOfCommentedPostsWithTag
    FROM Tags AS T
    LEFT JOIN Posts AS P_Excerpt ON T.ExcerptPostId = P_Excerpt.Id
    LEFT JOIN Posts AS P_Wiki ON T.WikiPostId = P_Wiki.Id
),
CombinedAnalysis AS (
    SELECT
        PDM.PostId,
        PDM.PostTitle,
        PDM.PostCreationDate,
        PDM.PostScore,
        PDM.ViewCount,
        PDM.AnswerCount,
        PDM.CommentCount,
        PDM.FavoriteCount,
        PDM.ActualPostOwnerDisplayName,
        UES.Reputation AS OwnerReputation,
        UES.TotalPostsCreated AS OwnerTotalPosts,
        PDM.TotalEditRevisions,
        PDM.WasClosedEventRecorded,
        PDM.PostAgeInDays,
        PDM.PrimaryTag,
        PDM.HasBountiedAnswer,
        PDM.LinkedPostCount,
        PDM.DuplicateOfCount,
        TP.TotalTagPosts,
        TP.TagPopularityRank,
        TP.AvgScoreOfCommentedPostsWithTag,
        CASE
            WHEN PDM.PostTypeId = 1 AND PDM.AnswerCount = 0 AND PDM.ViewCount > 5000 AND PDM.PostAgeInDays > 90 AND PDM.ClosedDate IS NULL THEN 'StaleHighViewQuestion'
            WHEN PDM.PostTypeId = 1 AND PDM.ClosedDate IS NOT NULL AND PDM.TotalEditRevisions >= 5 THEN 'HighlyEditedClosedQuestion'
            WHEN PDM.PostTypeId = 2 AND PDM.PostScore > 50 AND PDM.CommentCount > 10 AND PDM.HasBountiedAnswer THEN 'ExceptionalAnswer'
            WHEN PDM.PostScore < 0 AND PDM.CommentCount > 5 AND PDM.TotalEditRevisions = 0 THEN 'ControversialUneditedPost'
            ELSE 'Standard'
        END AS PostHealthStatus,
        ROW_NUMBER() OVER (PARTITION BY (UES.TotalPostsCreated / 100) * 100 ORDER BY PDM.PostScore DESC) AS RankInOwnerActivityTier,
        AVG(PDM.PostAgeInDays) OVER (PARTITION BY CAST(FLOOR(UES.Reputation / 1000) * 1000 AS INTEGER)) AS AvgPostAgeInReputationTier
    FROM PostDetailedMetrics AS PDM
    LEFT JOIN UserEngagementSummary AS UES ON PDM.OwnerUserId = UES.UserId
    LEFT JOIN TagPerformance AS TP ON PDM.PrimaryTag = TP.TagName
    WHERE PDM.OwnerUserId IS NOT NULL
      AND UES.Reputation IS NOT NULL
),
ProblematicPostCandidates AS (
    SELECT
        CA.PostId,
        CA.PostTitle,
        CA.PostCreationDate,
        CA.PostHealthStatus
    FROM CombinedAnalysis AS CA
    WHERE CA.PostHealthStatus = 'StaleHighViewQuestion'
    INTERSECT
    SELECT
        PH.PostId,
        P.Title AS PostTitle,
        P.CreationDate AS PostCreationDate,
        'N/A' AS PostHealthStatus
    FROM PostHistory AS PH
    JOIN Posts AS P ON PH.PostId = P.Id
    JOIN Users AS U ON PH.UserId = U.Id
    WHERE PH.PostHistoryTypeId IN (4, 5, 6)
      AND U.Reputation > 10000
)
SELECT
    PPC.PostId,
    PPC.PostTitle,
    PPC.PostCreationDate,
    CA.ActualPostOwnerDisplayName,
    CA.OwnerReputation,
    CA.PostScore,
    CA.ViewCount,
    CA.AnswerCount,
    CA.CommentCount,
    CA.FavoriteCount,
    CA.TotalEditRevisions,
    CA.PostHealthStatus,
    CA.PrimaryTag,
    CA.TotalTagPosts,
    CA.TagPopularityRank,
    CA.AvgScoreOfCommentedPostsWithTag,
    CA.HasBountiedAnswer,
    CA.LinkedPostCount,
    CA.DuplicateOfCount,
    CA.RankInOwnerActivityTier,
    CA.AvgPostAgeInReputationTier,
    (CA.PostScore * 0.4 + CA.ViewCount * 0.005 + CA.CommentCount * 0.2 + CA.FavoriteCount * 0.3 - (CA.PostAgeInDays / 365.0) * 5.0 + CASE WHEN CA.HasBountiedAnswer THEN 10 ELSE 0 END) AS PotentialEngagementScore,
    ('Owner: ' || CA.ActualPostOwnerDisplayName || ' (Rep:' || CAST(CA.OwnerReputation AS VARCHAR) || ') - Tags: <' || CA.PrimaryTag || '> - Health: ' || CA.PostHealthStatus) AS PostSummaryDescription,
    COALESCE(CAST(P.ClosedDate AS VARCHAR), 'No Closed Date') AS FinalClosedDateStatus
FROM ProblematicPostCandidates AS PPC
JOIN CombinedAnalysis AS CA ON PPC.PostId = CA.PostId
JOIN Posts AS P ON PPC.PostId = P.Id
WHERE CA.OwnerReputation > 5000
  AND CA.TotalEditRevisions >= 2
  AND CA.ViewCount > 10000
  AND CA.PostAgeInDays BETWEEN 180 AND 1095
  AND CA.PrimaryTag IS NOT NULL
  AND CA.PrimaryTag IN ('sql', 'performance', 'database', 'c#', 'java')
ORDER BY PotentialEngagementScore DESC, CA.PostCreationDate ASC
LIMIT 200;