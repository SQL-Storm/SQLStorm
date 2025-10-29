WITH UserContributionSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.UpVotes AS UserTotalUpVotesGiven,
        U.DownVotes AS UserTotalDownVotesGiven,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestionsAsked,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswersPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END), 0) AS QuestionsWithAcceptedAnswer,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 AND ParentQ.AcceptedAnswerId = P.Id THEN 1 ELSE 0 END), 0) AS AcceptedAnswersCount,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END), 0.0) AS AvgQuestionScore,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END), 0.0) AS AvgAnswerScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts ParentQ ON P.PostTypeId = 2 AND P.ParentId = ParentQ.Id
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes
),
UserEditActivitySummary AS (
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalEditEventsMade,
        COUNT(DISTINCT PH.PostId) AS UniquePostsEdited,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS MajorEditCount,
        SUM(CASE WHEN P.OwnerUserId = PH.UserId THEN 1 ELSE 0 END) AS SelfEditHistoryCount
    FROM PostHistory PH
    INNER JOIN Posts P ON PH.PostId = P.Id
    WHERE PH.UserId IS NOT NULL
      AND PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24)
      AND P.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '5 year')
    GROUP BY PH.UserId
),
PostHistoricalMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.OwnerUserId,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        COALESCE(COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24)), 0) AS EditEventCount,
        COALESCE(COUNT(DISTINCT PH.UserId) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) AND PH.UserId IS NOT NULL), 0) AS UniqueEditorCount,
        MAX(PH.CreationDate) AS LastHistoryDate,
        (
            SELECT MAX(PH_Corr.CreationDate)
            FROM PostHistory PH_Corr
            WHERE PH_Corr.PostId = P.Id
              AND PH_Corr.PostHistoryTypeId = 5
        ) AS LastBodyEditDate,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS CommentCount,
        COALESCE(SUM(CASE WHEN V.VoteTypeId IN (2, 5) THEN 1 ELSE 0 END), 0) AS UpvoteCount,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvoteCount
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId
    WHERE P.PostTypeId IN (1, 2)
      AND P.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '3 year')
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId, P.LastActivityDate, P.Title, P.Tags
),
RankedUserPosts AS (
    SELECT
        PHM.OwnerUserId AS UserId,
        PHM.PostId,
        PHM.PostTypeId,
        PHM.PostScore,
        PHM.ViewCount,
        PHM.CommentCount,
        PHM.UpvoteCount,
        PHM.DownvoteCount,
        PHM.EditEventCount,
        PHM.LastBodyEditDate,
        (PHM.UpvoteCount - PHM.DownvoteCount) AS NetVotes,
        ROW_NUMBER() OVER (PARTITION BY PHM.OwnerUserId, PHM.PostTypeId ORDER BY PHM.PostScore DESC, PHM.ViewCount DESC) AS RankByScoreViews,
        DENSE_RANK() OVER (ORDER BY PHM.ViewCount DESC, PHM.PostScore DESC) AS GlobalPostPopularityRank
    FROM PostHistoricalMetrics PHM
    WHERE PHM.PostTypeId IN (1, 2)
),
CommunityMagnetPosts AS (
    SELECT
        PHM.PostId,
        PHM.OwnerUserId,
        PHM.Title,
        PHM.PostTypeId,
        PHM.PostCreationDate,
        PHM.PostScore,
        PHM.ViewCount,
        PHM.CommentCount,
        PHM.UpvoteCount,
        PHM.EditEventCount,
        PHM.UniqueEditorCount,
        PHM.LastHistoryDate,
        PHM.LastBodyEditDate,
        (PHM.UpvoteCount + PHM.DownvoteCount) AS TotalVotes,
        (PHM.CommentCount * 1.0 / NULLIF(PHM.ViewCount, 0)) AS CommentViewRatio,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - PHM.PostCreationDate)) / (60 * 60 * 24) AS PostAgeDays,
        NULLIF(PHM.UniqueEditorCount, 0) * 1.0 / NULLIF(PHM.EditEventCount, 0) AS EditorDiversityRatio,
        CASE
            WHEN PHM.PostTypeId = 1 THEN 'Question'
            WHEN PHM.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeDescription,
        PHM.Tags,
        (
            PHM.PostScore * 2 + PHM.ViewCount / 100 + PHM.UpvoteCount * 5 + PHM.CommentCount * 3 + PHM.EditEventCount * 2
            + CASE
                WHEN PHM.Tags LIKE '%<sql>%' OR PHM.Tags LIKE '%<database>%' THEN 50
                WHEN PHM.Tags LIKE '%<performance>%' OR PHM.Tags LIKE '%<optimization>%' THEN 75
                WHEN PHM.Tags IS NULL OR PHM.Tags = '' THEN -20
                ELSE 0
              END
        ) AS CommunityEngagementScore
    FROM PostHistoricalMetrics PHM
    WHERE PHM.ViewCount > 500
      AND PHM.EditEventCount > 3
      AND PHM.CommentCount > 5
      AND PHM.PostScore > 10
      AND PHM.PostTypeId = 1
      AND (PHM.LastBodyEditDate IS NOT NULL OR PHM.LastHistoryDate IS NOT NULL)
),
HighUpvotedPostsByUser AS (
    SELECT UserId, SUM(Votes) AS TotalHighUpvotedPostsScore
    FROM (
        SELECT P.OwnerUserId AS UserId, UpvotedQuestion.Votes
        FROM Posts P
        INNER JOIN (
            SELECT PostId, COUNT(Id) AS Votes
            FROM Votes
            WHERE VoteTypeId = 2
            GROUP BY PostId
            HAVING COUNT(Id) > 50
        ) AS UpvotedQuestion ON P.Id = UpvotedQuestion.PostId
        WHERE P.PostTypeId = 1

        UNION ALL

        SELECT P.OwnerUserId AS UserId, UpvotedAnswer.Votes
        FROM Posts P
        INNER JOIN (
            SELECT PostId, COUNT(Id) AS Votes
            FROM Votes
            WHERE VoteTypeId = 2
            GROUP BY PostId
            HAVING COUNT(Id) > 20
        ) AS UpvotedAnswer ON P.Id = UpvotedAnswer.PostId
        WHERE P.PostTypeId = 2
    ) AS CombinedHighUpvotedPosts
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
UserInfluenceTierCalc AS (
    -- Precompute user influence tier as a column to avoid nested window functions
    SELECT
        UCS.*,
        NTILE(5) OVER (ORDER BY UCS.Reputation DESC, UCS.AcceptedAnswersCount DESC, UCS.AvgQuestionScore DESC, UCS.AvgAnswerScore DESC) AS UserInfluenceTier
    FROM UserContributionSummary UCS
)
SELECT
    UIC.UserId,
    CONCAT(COALESCE(UIC.DisplayName, 'Anonymous'), ' (ID:', UIC.UserId, ')') AS UserIdentifier,
    UIC.Reputation,
    UIC.UserInfluenceTier AS UserInfluenceTier,
    UIC.TotalQuestionsAsked,
    UIC.TotalAnswersPosted,
    UIC.AcceptedAnswersCount,
    (UIC.AcceptedAnswersCount * 1.0 / NULLIF(UIC.TotalAnswersPosted, 0)) AS AnswerAcceptanceRate,
    UIC.AvgQuestionScore,
    UIC.AvgAnswerScore,
    COALESCE(UES.TotalEditEventsMade, 0) AS UserTotalEditEventsMade,
    COALESCE(UES.SelfEditHistoryCount, 0) AS UserSelfEditCount,
    COALESCE(HUPB.TotalHighUpvotedPostsScore, 0) AS TotalScoreFromHighUpvotedPosts,
    (UIC.UserTotalUpVotesGiven + UIC.UserTotalDownVotesGiven) AS TotalVotesGivenByAUser,
    TRQ.PostId AS TopQuestionId,
    TRQ.PostScore AS TopQuestionScore,
    TRQ.ViewCount AS TopQuestionViews,
    TRQ.CommentCount AS TopQuestionComments,
    TRQ.NetVotes AS TopQuestionNetVotes,
    TRQ.EditEventCount AS TopQuestionEditEvents,
    TRQ.LastBodyEditDate AS TopQuestionLastBodyEditDate,
    TRA.PostId AS TopAnswerId,
    TRA.PostScore AS TopAnswerScore,
    TRA.ViewCount AS TopAnswerViews,
    TRA.CommentCount AS TopAnswerComments,
    TRA.NetVotes AS TopAnswerNetVotes,
    TRA.EditEventCount AS TopAnswerEditEvents,
    TRA.LastBodyEditDate AS TopAnswerLastBodyEditDate,
    CMP.PostId AS MagnetPostId,
    CMP.Title AS MagnetPostTitle,
    CMP.CommunityEngagementScore AS MagnetPostEngagementScore,
    CMP.PostTypeDescription AS MagnetPostType,
    CMP.CommentViewRatio AS MagnetCommentViewRatio,
    CMP.EditorDiversityRatio AS MagnetEditorDiversityRatio,
    (
        SELECT STRING_AGG(LOWER(tag), ';')
        FROM (
            SELECT UNNEST(string_to_array(SUBSTRING(COALESCE(CMP.Tags, '<>'), 2, LENGTH(COALESCE(CMP.Tags, '<>'))-2), '><')) AS tag
        ) t
        WHERE tag IS NOT NULL AND tag != ''
        LIMIT 3
    ) AS TopTagsInMagnetPost,
    -- Average total upvotes for all posts by users in the same influence tier:
    AVG(PHM_AvgTier.UpvoteCount) OVER (PARTITION BY UIC.UserInfluenceTier) AS AvgTierPostUpvotes,
    (UIC.AcceptedAnswersCount > 0 AND UIC.TotalQuestionsAsked > 0 AND (UES.SelfEditHistoryCount > 0 OR TRQ.EditEventCount > 0 OR TRA.EditEventCount > 0)) AS HighlyEngagedAndSuccessful
FROM UserInfluenceTierCalc UIC
LEFT JOIN UserEditActivitySummary UES ON UIC.UserId = UES.UserId
LEFT JOIN HighUpvotedPostsByUser HUPB ON UIC.UserId = HUPB.UserId
LEFT JOIN RankedUserPosts TRQ ON UIC.UserId = TRQ.UserId AND TRQ.PostTypeId = 1 AND TRQ.RankByScoreViews = 1
LEFT JOIN RankedUserPosts TRA ON UIC.UserId = TRA.UserId AND TRA.PostTypeId = 2 AND TRA.RankByScoreViews = 1
LEFT JOIN CommunityMagnetPosts CMP ON UIC.UserId = CMP.OwnerUserId AND CMP.PostId = TRQ.PostId
LEFT JOIN PostHistoricalMetrics PHM_AvgTier ON UIC.UserId = PHM_AvgTier.OwnerUserId
WHERE UIC.Reputation > 5000
  AND (UIC.TotalQuestionsAsked > 0 OR UIC.TotalAnswersPosted > 0)
  AND UIC.UserCreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '10 year')
  AND (TRQ.PostId IS NOT NULL OR TRA.PostId IS NOT NULL)
GROUP BY
    UIC.UserId,
    UIC.DisplayName,
    UIC.Reputation,
    UIC.UserInfluenceTier,
    UIC.TotalQuestionsAsked,
    UIC.TotalAnswersPosted,
    UIC.AcceptedAnswersCount,
    UIC.AvgQuestionScore,
    UIC.AvgAnswerScore,
    UIC.UserTotalUpVotesGiven,
    UIC.UserTotalDownVotesGiven,
    UES.TotalEditEventsMade,
    UES.SelfEditHistoryCount,
    HUPB.TotalHighUpvotedPostsScore,
    TRQ.PostId,
    TRQ.PostScore,
    TRQ.ViewCount,
    TRQ.CommentCount,
    TRQ.NetVotes,
    TRQ.EditEventCount,
    TRQ.LastBodyEditDate,
    TRA.PostId,
    TRA.PostScore,
    TRA.ViewCount,
    TRA.CommentCount,
    TRA.NetVotes,
    TRA.EditEventCount,
    TRA.LastBodyEditDate,
    CMP.PostId,
    CMP.Title,
    CMP.CommunityEngagementScore,
    CMP.PostTypeDescription,
    CMP.CommentViewRatio,
    CMP.EditorDiversityRatio,
    CMP.Tags,
    PHM_AvgTier.UpvoteCount,
    UIC.UserCreationDate
ORDER BY UserInfluenceTier ASC, UIC.Reputation DESC, TotalScoreFromHighUpvotedPosts DESC
LIMIT 200;