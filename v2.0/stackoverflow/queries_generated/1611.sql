-- {"query": "1611.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3557} 

WITH UserContributionSummary AS (
    -- Aggregates various metrics for users based on their owned posts
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.UpVotes AS UserTotalUpVotesGiven,
        U.DownVotes AS UserTotalDownVotesGiven,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestionsAsked,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswersPosted,
        -- Count of questions asked by the user that have an accepted answer
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END), 0) AS QuestionsWithAcceptedAnswer,
        -- Count of answers posted by the user that were accepted for their parent question
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 AND ParentQ.AcceptedAnswerId = P.Id THEN 1 ELSE 0 END), 0) AS AcceptedAnswersCount,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END), 0.0) AS AvgQuestionScore,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END), 0.0) AS AvgAnswerScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    -- Join to get the parent question for answers to check for accepted answers
    LEFT JOIN Posts ParentQ ON P.PostTypeId = 2 AND P.ParentId = ParentQ.Id
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes
),
UserEditActivitySummary AS (
    -- Summarizes editing activity performed by each user
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalEditEventsMade,
        COUNT(DISTINCT PH.PostId) AS UniquePostsEdited,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS MajorEditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN P.OwnerUserId = PH.UserId THEN 1 ELSE 0 END) AS SelfEditHistoryCount -- Edits made by user on their own posts
    FROM PostHistory PH
    INNER JOIN Posts P ON PH.PostId = P.Id
    WHERE PH.UserId IS NOT NULL
      AND PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) -- Specific PostHistoryTypes for various edits/rollbacks/suggestions
      AND P.CreationDate >= (CURRENT_DATE - INTERVAL '5 year') -- Only consider recent post edits
    GROUP BY PH.UserId
),
PostHistoricalMetrics AS (
    -- Calculates various metrics for posts, including edit history and voting patterns
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
        -- Correlated Subquery to find the latest body edit date for a post
        (
            SELECT MAX(PH_Corr.CreationDate)
            FROM PostHistory PH_Corr
            WHERE PH_Corr.PostId = P.Id
              AND PH_Corr.PostHistoryTypeId = 5 -- Body Edit (PostHistoryType 5)
        ) AS LastBodyEditDate,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS CommentCount,
        COALESCE(SUM(CASE WHEN V.VoteTypeId IN (2, 5) THEN 1 ELSE 0 END), 0) AS UpvoteCount, -- UpMod, Favorite
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvoteCount -- DownMod
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId
    WHERE P.PostTypeId IN (1, 2) -- Only Questions (1) and Answers (2)
      AND P.CreationDate >= (CURRENT_DATE - INTERVAL '3 year') -- Filter for recent posts
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId, P.LastActivityDate, P.Title, P.Tags
),
RankedUserPosts AS (
    -- Ranks posts by score and views for each user and post type
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
    -- Identifies 'community magnet' posts based on high activity and engagement scores
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
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - PHM.PostCreationDate)) / (60 * 60 * 24) AS PostAgeDays, -- Age in days
        NULLIF(PHM.UniqueEditorCount, 0) * 1.0 / NULLIF(PHM.EditEventCount, 0) AS EditorDiversityRatio,
        CASE
            WHEN PHM.PostTypeId = 1 THEN 'Question'
            WHEN PHM.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other' -- Fallback for unexpected PostTypeIds
        END AS PostTypeDescription,
        PHM.Tags,
        -- Complex calculation for Community Engagement Score, including tag-based bonuses
        (
            PHM.PostScore * 2 + PHM.ViewCount / 100 + PHM.UpvoteCount * 5 + PHM.CommentCount * 3 + PHM.EditEventCount * 2
            + CASE
                WHEN PHM.Tags LIKE '%<sql>%' OR PHM.Tags LIKE '%<database>%' THEN 50
                WHEN PHM.Tags LIKE '%<performance>%' OR PHM.Tags LIKE '%<optimization>%' THEN 75
                WHEN PHM.Tags IS NULL OR PHM.Tags = '' THEN -20 -- Penalty for missing tags
                ELSE 0
              END
        ) AS CommunityEngagementScore
    FROM PostHistoricalMetrics PHM
    WHERE PHM.ViewCount > 500
      AND PHM.EditEventCount > 3
      AND PHM.CommentCount > 5
      AND PHM.PostScore > 10
      AND PHM.PostTypeId = 1 -- Only questions can be "community magnets" in this context
      -- NULL logic: ensure there's a history of activity or edit
      AND (PHM.LastBodyEditDate IS NOT NULL OR PHM.LastHistoryDate IS NOT NULL)
),
HighUpvotedPostsByUser AS (
    -- Identifies posts with exceptionally high upvote counts for questions and answers separately, then aggregates by user
    SELECT UserId, SUM(Votes) AS TotalHighUpvotedPostsScore
    FROM (
        -- High upvoted Questions
        SELECT P.OwnerUserId AS UserId, UpvotedQuestion.Votes
        FROM Posts P
        INNER JOIN (
            SELECT PostId, COUNT(Id) AS Votes
            FROM Votes
            WHERE VoteTypeId = 2 -- UpMod
            GROUP BY PostId
            HAVING COUNT(Id) > 50
        ) AS UpvotedQuestion ON P.Id = UpvotedQuestion.PostId
        WHERE P.PostTypeId = 1

        UNION ALL -- Set operator

        -- High upvoted Answers
        SELECT P.OwnerUserId AS UserId, UpvotedAnswer.Votes
        FROM Posts P
        INNER JOIN (
            SELECT PostId, COUNT(Id) AS Votes
            FROM Votes
            WHERE VoteTypeId = 2 -- UpMod
            GROUP BY PostId
            HAVING COUNT(Id) > 20
        ) AS UpvotedAnswer ON P.Id = UpvotedAnswer.PostId
        WHERE P.PostTypeId = 2
    ) AS CombinedHighUpvotedPosts
    WHERE UserId IS NOT NULL -- Exclude community owned posts (OwnerUserId = -1)
    GROUP BY UserId
)
-- Main Query: Combines all CTEs to find influential users and their significant posts
SELECT
    UCS.UserId,
    CONCAT(COALESCE(UCS.DisplayName, 'Anonymous'), ' (ID:', UCS.UserId, ')') AS UserIdentifier, -- String expression with NULL logic
    UCS.Reputation,
    NTILE(5) OVER (ORDER BY UCS.Reputation DESC, UCS.AcceptedAnswersCount DESC, UCS.AvgQuestionScore DESC, UCS.AvgAnswerScore DESC) AS UserInfluenceTier, -- Window function
    UCS.TotalQuestionsAsked,
    UCS.TotalAnswersPosted,
    UCS.AcceptedAnswersCount,
    (UCS.AcceptedAnswersCount * 1.0 / NULLIF(UCS.TotalAnswersPosted, 0)) AS AnswerAcceptanceRate,
    UCS.AvgQuestionScore,
    UCS.AvgAnswerScore,
    COALESCE(UES.TotalEditEventsMade, 0) AS UserTotalEditEventsMade,
    COALESCE(UES.SelfEditHistoryCount, 0) AS UserSelfEditCount,
    COALESCE(HUPB.TotalHighUpvotedPostsScore, 0) AS TotalScoreFromHighUpvotedPosts, -- Joined from set operator CTE
    (UCS.UserTotalUpVotesGiven + UCS.UserTotalDownVotesGiven) AS TotalVotesGivenByAUser,
    -- Get the user's top-ranked question
    TRQ.PostId AS TopQuestionId,
    TRQ.PostScore AS TopQuestionScore,
    TRQ.ViewCount AS TopQuestionViews,
    TRQ.CommentCount AS TopQuestionComments,
    TRQ.NetVotes AS TopQuestionNetVotes,
    TRQ.EditEventCount AS TopQuestionEditEvents,
    TRQ.LastBodyEditDate AS TopQuestionLastBodyEditDate,
    -- Get the user's top-ranked answer
    TRA.PostId AS TopAnswerId,
    TRA.PostScore AS TopAnswerScore,
    TRA.ViewCount AS TopAnswerViews,
    TRA.CommentCount AS TopAnswerComments,
    TRA.NetVotes AS TopAnswerNetVotes,
    TRA.EditEventCount AS TopAnswerEditEvents,
    TRA.LastBodyEditDate AS TopAnswerLastBodyEditDate,
    -- Information about community magnet posts owned by the user
    CMP.PostId AS MagnetPostId,
    CMP.Title AS MagnetPostTitle,
    CMP.CommunityEngagementScore AS MagnetPostEngagementScore,
    CMP.PostTypeDescription AS MagnetPostType,
    CMP.CommentViewRatio AS MagnetCommentViewRatio,
    CMP.EditorDiversityRatio AS MagnetEditorDiversityRatio,
    -- Correlated subquery to find top tags in a magnet post, using string_to_array and UNNEST
    (
        SELECT STRING_AGG(LOWER(tag), ';')
        FROM UNNEST(string_to_array(SUBSTRING(COALESCE(CMP.Tags, '<>'), 2, LENGTH(COALESCE(CMP.Tags, '<>'))-2), '><')) AS tag
        WHERE tag IS NOT NULL AND tag != ''
        LIMIT 3
    ) AS TopTagsInMagnetPost,
    -- Another window function: Average total upvotes for all posts by users in the same influence tier
    AVG(PHM_AvgTier.UpvoteCount) OVER (PARTITION BY NTILE(5) OVER (ORDER BY UCS.Reputation DESC, UCS.AcceptedAnswersCount DESC, UCS.AvgQuestionScore DESC, UCS.AvgAnswerScore DESC)) AS AvgTierPostUpvotes,
    -- Complex NULL logic and conditional check
    (UCS.AcceptedAnswersCount > 0 AND UCS.TotalQuestionsAsked > 0 AND (UES.SelfEditHistoryCount > 0 OR TRQ.EditEventCount > 0 OR TRA.EditEventCount > 0)) AS HighlyEngagedAndSuccessful
FROM UserContributionSummary UCS
LEFT JOIN UserEditActivitySummary UES ON UCS.UserId = UES.UserId
LEFT JOIN HighUpvotedPostsByUser HUPB ON UCS.UserId = HUPB.UserId
LEFT JOIN RankedUserPosts TRQ ON UCS.UserId = TRQ.UserId AND TRQ.PostTypeId = 1 AND TRQ.RankByScoreViews = 1 -- Top Question
LEFT JOIN RankedUserPosts TRA ON UCS.UserId = TRA.UserId AND TRA.PostTypeId = 2 AND TRA.RankByScoreViews = 1 -- Top Answer
LEFT JOIN CommunityMagnetPosts CMP ON UCS.UserId = CMP.OwnerUserId AND CMP.PostId = TRQ.PostId -- Check if top question is also a magnet post
LEFT JOIN PostHistoricalMetrics PHM_AvgTier ON UCS.UserId = PHM_AvgTier.OwnerUserId -- For avg post upvotes in tier window function
WHERE UCS.Reputation > 5000 -- Focus on more influential users
  AND (UCS.TotalQuestionsAsked > 0 OR UCS.TotalAnswersPosted > 0) -- Users must have contributed posts
  AND UCS.UserCreationDate >= (CURRENT_DATE - INTERVAL '10 year') -- Active users within the last decade
  AND (TRQ.PostId IS NOT NULL OR TRA.PostId IS NOT NULL) -- Users must have at least one ranked post
ORDER BY UserInfluenceTier ASC, UCS.Reputation DESC, TotalScoreFromHighUpvotedPosts DESC
LIMIT 200;
