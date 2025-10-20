-- {"query": "49083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2281} 

WITH UserBaseStats AS (
    -- Summarize basic user information, including reputation and badge counts
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 2) AS SilverBadges,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadges
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
),
PostDetailsExpanded AS (
    -- Extract detailed information for each post, including parsed tags and historical event counts
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount AS QuestionAnswerCount, -- Only relevant for PostTypeId = 1 (Questions)
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        -- Parse the Tags string into an array, handling empty/NULL cases
        CASE WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
             THEN string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')
             ELSE ARRAY[]::VARCHAR[]
        END AS TagArray,
        COUNT(DISTINCT C.Id) AS PostCommentCount,
        COUNT(DISTINCT PH_Edit.Id) AS EditCount, -- Count of title/body/tags edits or rollbacks
        COUNT(DISTINCT PH_Close.Id) AS CloseCount, -- Count of close events
        COUNT(DISTINCT PH_Reopen.Id) AS ReopenCount, -- Count of reopen events
        -- Determine if the post is an accepted answer to its parent question
        MAX(CASE WHEN P.PostTypeId = 2 AND ParentQ.AcceptedAnswerId = P.Id THEN 1 ELSE 0 END) AS IsAcceptedAnswer
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN PostHistory PH_Edit ON P.Id = PH_Edit.PostId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    LEFT JOIN PostHistory PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    LEFT JOIN PostHistory PH_Reopen ON P.Id = PH_Reopen.PostId AND PH_Reopen.PostHistoryTypeId = 11
    LEFT JOIN Posts ParentQ ON P.PostTypeId = 2 AND P.ParentId = ParentQ.Id AND ParentQ.PostTypeId = 1
    WHERE P.OwnerUserId IS NOT NULL -- Focus on posts by actual users, not community or deleted users
    GROUP BY P.Id, P.OwnerUserId, P.PostTypeId, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.CreationDate, P.LastActivityDate, P.Tags
),
UserContentSummary AS (
    -- Aggregate post-level statistics to a user level
    SELECT
        PDE.OwnerUserId AS UserId,
        COUNT(DISTINCT CASE WHEN PDE.PostTypeId = 1 THEN PDE.PostId END) AS QuestionsPosted,
        COUNT(DISTINCT CASE WHEN PDE.PostTypeId = 2 THEN PDE.PostId END) AS AnswersPosted,
        SUM(PDE.PostScore) AS TotalPostsScore,
        SUM(CASE WHEN PDE.PostTypeId = 1 THEN PDE.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(PDE.FavoriteCount) AS TotalPostsFavorites,
        SUM(PDE.QuestionAnswerCount) AS TotalAnswersReceivedOnQuestions,
        SUM(PDE.PostCommentCount) AS TotalCommentsOnOwnPosts,
        SUM(PDE.EditCount) AS TotalEditsToOwnPosts,
        SUM(PDE.CloseCount) AS TotalPostsClosed,
        SUM(PDE.ReopenCount) AS TotalPostsReopened,
        SUM(PDE.IsAcceptedAnswer) AS AcceptedAnswersCount
    FROM PostDetailsExpanded PDE
    GROUP BY PDE.OwnerUserId
),
TagAverageScores AS (
    -- Calculate the average score for posts associated with each unique tag
    SELECT
        UNNEST(PDE.TagArray) AS TagName,
        AVG(PDE.PostScore) AS AvgScore,
        COUNT(PDE.PostId) AS PostCountWithTag
    FROM PostDetailsExpanded PDE
    WHERE ARRAY_LENGTH(PDE.TagArray, 1) > 0
    GROUP BY UNNEST(PDE.TagArray)
),
UserTagContribution AS (
    -- For each user, determine their average post score for tags they contribute to
    SELECT
        PDE.OwnerUserId AS UserId,
        AVG(TAS.AvgScore) AS AvgUserTagPerformanceScore,
        COUNT(DISTINCT UNNEST(PDE.TagArray)) AS UniqueTagsContributed
    FROM PostDetailsExpanded PDE
    CROSS JOIN UNNEST(PDE.TagArray) AS UserTag (TagName)
    JOIN TagAverageScores TAS ON UserTag.TagName = TAS.TagName
    WHERE ARRAY_LENGTH(PDE.TagArray, 1) > 0
    GROUP BY PDE.OwnerUserId
)
-- Final result set combining all aggregated and calculated metrics for users
SELECT
    UBS.UserId,
    UBS.DisplayName,
    UBS.Reputation,
    UBS.GoldBadges,
    UBS.SilverBadges,
    UBS.BronzeBadges,
    COALESCE(UCS.QuestionsPosted, 0) AS QuestionsPosted,
    COALESCE(UCS.AnswersPosted, 0) AS AnswersPosted,
    COALESCE(UCS.TotalPostsScore, 0) AS TotalPostsScore,
    COALESCE(UCS.TotalQuestionViews, 0) AS TotalQuestionViews,
    COALESCE(UCS.TotalPostsFavorites, 0) AS TotalPostsFavorites,
    COALESCE(UCS.AcceptedAnswersCount, 0) AS AcceptedAnswersCount,
    COALESCE(UTC.AvgUserTagPerformanceScore, 0.0) AS AvgUserTagPerformanceScore,
    COALESCE(UTC.UniqueTagsContributed, 0) AS UniqueTagsContributed,
    -- A composite "UserImpactScore" calculated from various weighted metrics
    (
        UBS.Reputation * 0.05 +                             -- Contribution from overall reputation
        UBS.GoldBadges * 100 +                              -- High value for gold badges
        UBS.SilverBadges * 50 +                             -- Medium value for silver badges
        UBS.BronzeBadges * 10 +                             -- Low value for bronze badges
        COALESCE(UCS.QuestionsPosted, 0) * 3 +              -- Reward for asking questions
        COALESCE(UCS.AnswersPosted, 0) * 6 +                -- Higher reward for providing answers
        COALESCE(UCS.TotalPostsScore, 0) * 0.2 +            -- Value from total post scores
        COALESCE(UCS.TotalQuestionViews, 0) * 0.0005 +      -- Minor value from post views
        COALESCE(UCS.TotalPostsFavorites, 0) * 1.5 +        -- Moderate value from post favorites
        COALESCE(UCS.AcceptedAnswersCount, 0) * 10 +        -- Significant value for accepted answers
        COALESCE(UTC.AvgUserTagPerformanceScore, 0.0) * 0.1 + -- Value from performance in contributed tags
        COALESCE(UTC.UniqueTagsContributed, 0) * 2 -        -- Value for contributing to diverse tags
        COALESCE(UCS.TotalPostsClosed, 0) * 5               -- Penalty for having posts closed
    ) AS UserImpactScore,
    -- Rank users based on their calculated impact score
    RANK() OVER (ORDER BY (
        UBS.Reputation * 0.05 +
        UBS.GoldBadges * 100 +
        UBS.SilverBadges * 50 +
        UBS.BronzeBadges * 10 +
        COALESCE(UCS.QuestionsPosted, 0) * 3 +
        COALESCE(UCS.AnswersPosted, 0) * 6 +
        COALESCE(UCS.TotalPostsScore, 0) * 0.2 +
        COALESCE(UCS.TotalQuestionViews, 0) * 0.0005 +
        COALESCE(UCS.TotalPostsFavorites, 0) * 1.5 +
        COALESCE(UCS.AcceptedAnswersCount, 0) * 10 +
        COALESCE(UTC.AvgUserTagPerformanceScore, 0.0) * 0.1 +
        COALESCE(UTC.UniqueTagsContributed, 0) * 2 -
        COALESCE(UCS.TotalPostsClosed, 0) * 5
    ) DESC) AS OverallImpactRank
FROM UserBaseStats UBS
LEFT JOIN UserContentSummary UCS ON UBS.UserId = UCS.UserId
LEFT JOIN UserTagContribution UTC ON UBS.UserId = UTC.UserId
WHERE UBS.Reputation > 500 -- Filter for users with a minimum reputation
  AND (COALESCE(UCS.QuestionsPosted, 0) > 0 OR COALESCE(UCS.AnswersPosted, 0) > 0) -- Users must have posted questions or answers
  AND UBS.LastAccessDate >= (NOW() - INTERVAL '1 year') -- Only consider users active in the last year
ORDER BY UserImpactScore DESC, UBS.Reputation DESC
LIMIT 1000;
