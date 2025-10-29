-- {"query": "1192.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2809} 
WITH UserActivitySummary AS (
    -- Aggregates user activity, badge status, and basic statistics.
    -- Includes boolean flag for having a gold badge and total posts/comments.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT V.PostId) FILTER (WHERE V.VoteTypeId = 2) AS UpvotesGivenCount,
        COUNT(DISTINCT V.PostId) FILTER (WHERE V.VoteTypeId = 3) AS DownvotesGivenCount,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        MAX(C.CreationDate) AS LastCommentActivityDate,
        BOOL_OR(B.Class = 1) AS HasGoldBadge -- True if the user has at least one gold badge
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
PostDetailMetrics AS (
    -- Gathers detailed metrics and history for each post, including edit counts,
    -- last close reason, and parsed tags.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.ParentId,
        (SELECT COUNT(DISTINCT ph.Id) FROM PostHistory ph WHERE ph.PostId = P.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS EditCount,
        (SELECT COUNT(DISTINCT ph.Id) FROM PostHistory ph WHERE ph.PostId = P.Id AND ph.PostHistoryTypeId = 10) AS CloseVoteHistoryCount,
        (
            SELECT CR.Name
            FROM PostHistory PH_Close
            INNER JOIN CloseReasonTypes CR ON CAST(PH_Close.Comment AS smallint) = CR.Id
            WHERE PH_Close.PostId = P.Id AND PH_Close.PostHistoryTypeId = 10
            ORDER BY PH_Close.CreationDate DESC
            LIMIT 1
        ) AS LastCloseReason,
        COALESCE(ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'), 1), 0) AS TagCount,
        (
            SELECT STRING_AGG(T.TagName, ', ')
            FROM Tags T
            WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND T.TagName = ANY(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))
        ) AS TagNames
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
RankedHighQualityQuestions AS (
    -- Identifies and ranks high-quality questions based on various criteria and window functions.
    SELECT
        PDM.PostId,
        PDM.PostTypeId,
        PDM.OwnerUserId,
        PDM.CreationDate,
        PDM.Score,
        PDM.ViewCount,
        PDM.AnswerCount,
        PDM.CommentCount,
        PDM.FavoriteCount,
        PDM.ClosedDate,
        PDM.LastEditDate,
        PDM.LastActivityDate,
        PDM.EditCount,
        PDM.CloseVoteHistoryCount,
        PDM.LastCloseReason,
        PDM.TagCount,
        PDM.TagNames,
        CAST(PDM.Score AS NUMERIC) / NULLIF(PDM.ViewCount, 0) AS ScorePerViewRatio,
        ROW_NUMBER() OVER (ORDER BY PDM.Score DESC, PDM.ViewCount DESC, PDM.FavoriteCount DESC) AS OverallQuestionRank,
        AVG(PDM.Score) OVER (PARTITION BY PDM.OwnerUserId) AS AvgOwnerQuestionScore,
        LAG(PDM.CreationDate, 1) OVER (PARTITION BY PDM.OwnerUserId ORDER BY PDM.CreationDate) AS PreviousQuestionDate,
        EXTRACT(EPOCH FROM (PDM.CreationDate - LAG(PDM.CreationDate, 1) OVER (PARTITION BY PDM.OwnerUserId ORDER BY PDM.CreationDate))) / 86400 AS DaysSincePreviousQuestion
    FROM PostDetailMetrics PDM
    WHERE PDM.PostTypeId = 1 -- Questions
      AND PDM.ViewCount > 500
      AND PDM.Score > 10
      AND PDM.AnswerCount > 0
      AND PDM.ClosedDate IS NULL -- Only open questions
      AND PDM.LastEditDate IS NOT NULL AND PDM.LastEditDate > PDM.CreationDate -- Exclude unedited posts
),
RankedHighQualityAnswers AS (
    -- Identifies and ranks high-quality answers, linking to their parent questions for context.
    SELECT
        PDM.PostId,
        PDM.PostTypeId,
        PDM.OwnerUserId,
        PDM.CreationDate,
        PDM.Score,
        PDM.ViewCount, -- NULL for answers
        PDM.AnswerCount, -- NULL for answers
        PDM.CommentCount,
        PDM.FavoriteCount, -- NULL for answers
        PDM.ClosedDate, -- NULL for answers
        PDM.LastEditDate,
        PDM.LastActivityDate,
        PDM.EditCount,
        PDM.CloseVoteHistoryCount,
        PDM.LastCloseReason,
        PDM.TagCount, -- NULL for answers
        PQ.TagNames, -- Get tags from parent question
        CAST(PDM.Score AS NUMERIC) / NULLIF(PQ.Score, 0) AS AnswerScoreToQuestionScoreRatio,
        ROW_NUMBER() OVER (ORDER BY PDM.Score DESC, PDM.CommentCount DESC) AS OverallAnswerRank,
        AVG(PDM.Score) OVER (PARTITION BY PDM.OwnerUserId) AS AvgOwnerAnswerScore,
        SUM(PDM.Score) OVER (PARTITION BY PDM.ParentId) AS TotalAnswerScoreForQuestion
    FROM PostDetailMetrics PDM
    INNER JOIN Posts P_Parent ON PDM.ParentId = P_Parent.Id
    INNER JOIN PostDetailMetrics PQ ON P_Parent.Id = PQ.PostId -- Join to get question details, especially tags
    WHERE PDM.PostTypeId = 2 -- Answers
      AND PDM.Score > 20
      AND PDM.ParentId IS NOT NULL
      AND P_Parent.AcceptedAnswerId IS NOT NULL -- Question has an accepted answer
)
-- Main query combining high-quality questions and answers using UNION ALL,
-- then joining with user activity summary for detailed insights and final filtering.
SELECT
    UAS.DisplayName AS UserDisplayName,
    UAS.Reputation,
    UAS.UserViews,
    UAS.UpvotesGivenCount,
    UAS.DownvotesGivenCount,
    UAS.TotalPostsCreated,
    UAS.TotalCommentsMade,
    HQ.PostId,
    HQ.PostTypeId,
    HQ.PostCategory,
    HQ.CreationDate AS PostCreationDate,
    HQ.Score AS PostScore,
    HQ.ViewCount AS PostViewCount,
    HQ.AnswerCount AS PostAnswerCount,
    HQ.CommentCount AS PostCommentCount,
    HQ.FavoriteCount AS PostFavoriteCount,
    HQ.ClosedDate AS PostClosedDate,
    HQ.LastEditDate AS PostLastEditDate,
    HQ.LastActivityDate AS PostLastActivityDate,
    HQ.EditCount AS PostEditCount,
    HQ.CloseVoteHistoryCount,
    HQ.LastCloseReason,
    HQ.TagCount AS QuestionTagCount,
    HQ.TagNames AS QuestionTags,
    HQ.CombinedPerformanceMetric,
    HQ.CombinedPostRank AS PostRankInType,
    HQ.CombinedAvgOwnerScore AS AvgOwnerPostScoreOfType,
    HQ.DaysSincePreviousQuestion,
    HQ.AnswerSpecificMetric,
    HQ.ParentSpecificMetric,
    (
        SELECT COUNT(DISTINCT C.UserId)
        FROM Comments C
        WHERE C.PostId = HQ.PostId
          AND C.CreationDate > HQ.CreationDate
          AND C.Score > 0
    ) AS UniquePositiveCommentersAfterPost,
    PL.RelatedPostId AS LinkedToPostId,
    LT.Name AS LinkTypeName,
    DENSE_RANK() OVER (ORDER BY UAS.Reputation DESC, UAS.TotalPostsCreated DESC, UAS.UserViews DESC) AS OverallUserRank,
    SUM(HQ.Score) OVER (PARTITION BY UAS.UserId ORDER BY HQ.CreationDate) AS UserCumulativePostScore
FROM UserActivitySummary UAS
INNER JOIN (
    SELECT
        PostId, PostTypeId, OwnerUserId, CreationDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount,
        ClosedDate, LastEditDate, LastActivityDate, EditCount, CloseVoteHistoryCount, LastCloseReason, TagCount, TagNames,
        ScorePerViewRatio AS CombinedPerformanceMetric,
        OverallQuestionRank AS CombinedPostRank,
        AvgOwnerQuestionScore AS CombinedAvgOwnerScore,
        DaysSincePreviousQuestion,
        NULL AS AnswerSpecificMetric,
        NULL AS ParentSpecificMetric,
        'Question' AS PostCategory
    FROM RankedHighQualityQuestions
    WHERE OverallQuestionRank <= 500 -- Top N questions

    UNION ALL

    SELECT
        PostId, PostTypeId, OwnerUserId, CreationDate, Score, NULL AS ViewCount, NULL AS AnswerCount, CommentCount, NULL AS FavoriteCount,
        NULL AS ClosedDate, LastEditDate, LastActivityDate, EditCount, CloseVoteHistoryCount, LastCloseReason, NULL AS TagCount, TagNames,
        AnswerScoreToQuestionScoreRatio AS CombinedPerformanceMetric,
        OverallAnswerRank AS CombinedPostRank,
        AvgOwnerAnswerScore AS CombinedAvgOwnerScore,
        NULL AS DaysSincePreviousQuestion,
        AnswerScoreToQuestionScoreRatio AS AnswerSpecificMetric,
        TotalAnswerScoreForQuestion AS ParentSpecificMetric,
        'Answer' AS PostCategory
    FROM RankedHighQualityAnswers
    WHERE OverallAnswerRank <= 500 -- Top N answers
) AS HQ ON UAS.UserId = HQ.OwnerUserId
LEFT JOIN PostLinks PL ON HQ.PostId = PL.PostId AND PL.LinkTypeId = 1 -- Only 'Linked' types
LEFT JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
WHERE
    UAS.Reputation > 5000 -- Focus on more experienced users
    AND UAS.HasGoldBadge -- Users with at least one gold badge
    AND HQ.CreationDate >= (UAS.UserCreationDate + INTERVAL '1 year') -- Posts created at least 1 year after user registration
    AND HQ.LastCloseReason IS DISTINCT FROM 'Duplicate' -- Exclude posts explicitly closed as a 'Duplicate'
    AND (
        (HQ.PostCategory = 'Question' AND HQ.CombinedPerformanceMetric > 0.005 AND HQ.EditCount >= 3 AND HQ.TagCount >= 2 AND HQ.TagNames LIKE '%sql%')
        OR
        (HQ.PostCategory = 'Answer' AND HQ.CombinedPerformanceMetric > 0.2 AND HQ.CommentCount >= 5 AND HQ.EditCount >= 1 AND HQ.TagNames LIKE '%database%')
    )
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory PH_Del
        WHERE PH_Del.PostId = HQ.PostId AND PH_Del.PostHistoryTypeId = 12 -- Exclude any posts that have ever been deleted
    )
ORDER BY
    OverallUserRank ASC,
    HQ.PostCategory ASC,
    HQ.Score DESC,
    HQ.CreationDate DESC
LIMIT 1000;