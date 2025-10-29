-- {"query": "1933.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3262} 

WITH PostTagsAgg AS (
    -- Aggregates tags for posts, handling the delimited string format into a comma-separated list.
    SELECT
        P.Id AS PostId,
        STRING_AGG(DISTINCT T.TagName, ', ') FILTER (WHERE T.TagName IS NOT NULL) AS AssociatedTagsList
    FROM Posts P
    -- Use LATERAL UNNEST to expand the tags string (e.g., '<tag1><tag2>') into individual rows.
    JOIN LATERAL UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags) - 2), '><')) AS TagName_unnested ON TRUE
    JOIN Tags T ON TagName_unnested = T.TagName
    WHERE P.Tags IS NOT NULL AND length(P.Tags) > 2 -- Ensure tags string is not empty or just '<>'
    GROUP BY P.Id
),
UserEngagementSummary AS (
    -- Summarizes various engagement metrics for each user, including post counts, comment counts, and vote ratios.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(SUM(CASE WHEN P.PostTypeId IN (1, 2) THEN 1 ELSE 0 END), 0) AS TotalQuestionAnswerPosts,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotesGiven,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotesGiven,
        AVG(P.Score) FILTER (WHERE P.PostTypeId IN (1, 2)) AS AvgPostScoreByOwner,
        -- Calculate an upvote to downvote ratio, handling potential division by zero and NULLs.
        COALESCE(CAST(U.UpVotes AS DECIMAL) / NULLIF(U.DownVotes, 0), 0) AS UserUpDownVoteRatio,
        -- Correlated subquery to count gold badges for each user.
        (SELECT COUNT(DISTINCT B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadgesCount_Correlated
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    WHERE U.Reputation >= 100 -- Filter out very low reputation users early for performance.
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
),
PostDetailsAndActivity AS (
    -- Calculates various metrics and ranks for posts, including time-based differences and window functions.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        COALESCE(P.ClosedDate, '1900-01-01'::timestamp) AS PostClosedDate, -- Replace NULL ClosedDate with a sentinel value.
        EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 3600.0 AS HoursActiveUntilLastActivity, -- Time difference in hours.
        -- Correlated subquery to count comments made by the post owner during its active period.
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = P.Id AND C.UserId = P.OwnerUserId AND C.CreationDate >= P.CreationDate AND C.CreationDate <= P.LastActivityDate) AS OwnerCommentsDuringActivePeriod,
        AVG(P.Score) OVER (PARTITION BY P.PostTypeId) AS AvgScoreForPostType, -- Window function: average score for post type.
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.ViewCount DESC, P.Score DESC) AS RankByViewsScore, -- Window function: ranks posts by views and score within their type.
        LAG(P.CreationDate, 1, '1900-01-01'::timestamp) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostCreationDate, -- Window function: date of the user's previous post.
        COALESCE(PTA.AssociatedTagsList, 'No Tags') AS TagString, -- String expression and NULL logic for tags.
        -- Correlated subquery to find the date of the last body edit for the post.
        (SELECT MAX(PH.CreationDate) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 5) AS LastBodyEditDate,
        -- Correlated subquery to find the creation date of the accepted answer vote.
        (SELECT MIN(V.CreationDate) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 1) AS AcceptedVoteDate
    FROM Posts P
    LEFT JOIN PostTagsAgg PTA ON P.Id = PTA.PostId
    WHERE P.CreationDate >= NOW() - INTERVAL '4 year' -- Limit data to recent posts for relevance and performance.
    AND P.OwnerUserId IS NOT NULL AND P.OwnerUserId <> -1 -- Exclude community-owned posts and deleted users.
),
PostClosingAnalysis AS (
    -- Analyzes user involvement in post closing and reopening.
    SELECT
        U.Id AS UserId,
        COUNT(DISTINCT PH_Close.PostId) AS PostsVotedToClose,
        COUNT(DISTINCT PH_Reopen.PostId) AS PostsVotedToReopen,
        -- Correlated subquery counting specific "Duplicate" close votes by the user.
        (SELECT COUNT(DISTINCT PH_Close_Reason.Comment)
         FROM PostHistory PH_Close_Reason
         WHERE PH_Close_Reason.UserId = U.Id AND PH_Close_Reason.PostHistoryTypeId = 10 AND PH_Close_Reason.Comment = '101') AS DuplicateCloseVotesByMe,
        -- Categorizes user's closing/reopening behavior.
        CASE
            WHEN COUNT(DISTINCT PH_Close.PostId) > 0 AND COUNT(DISTINCT PH_Reopen.PostId) = 0 AND U.Reputation > 10000 THEN 'Pro-Close Senior User'
            WHEN COUNT(DISTINCT PH_Reopen.PostId) > 0 AND COUNT(DISTINCT PH_Close.PostId) = 0 THEN 'Pro-Reopen User'
            ELSE 'Mixed/Neutral Closer'
        END AS CloseReopenProfile
    FROM Users U
    LEFT JOIN PostHistory PH_Close ON U.Id = PH_Close.UserId AND PH_Close.PostHistoryTypeId = 10 AND PH_Close.CreationDate >= NOW() - INTERVAL '2 year'
    LEFT JOIN PostHistory PH_Reopen ON U.Id = PH_Reopen.UserId AND PH_Reopen.PostHistoryTypeId = 11 AND PH_Reopen.CreationDate >= NOW() - INTERVAL '2 year'
    GROUP BY U.Id, U.Reputation
),
LinkedAndDuplicatePostInfo AS (
    -- Gathers information about linked and duplicated posts using outer joins.
    SELECT
        P.Id AS PostId,
        COUNT(DISTINCT PL_Linked.RelatedPostId) AS OutgoingLinkedPostsCount,
        COUNT(DISTINCT PL_Duplicate.RelatedPostId) AS OutgoingDuplicateTargetCount,
        STRING_AGG(DISTINCT CAST(PL_Duplicate.RelatedPostId AS VARCHAR), ', ') FILTER (WHERE PL_Duplicate.RelatedPostId IS NOT NULL) AS DuplicateTargetIds,
        -- Correlated subquery to count incoming links to the post.
        (SELECT COUNT(DISTINCT InnerPL.PostId) FROM PostLinks InnerPL WHERE InnerPL.RelatedPostId = P.Id AND InnerPL.LinkTypeId = 1) AS IncomingLinkedCount
    FROM Posts P
    LEFT JOIN PostLinks PL_Linked ON P.Id = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1
    LEFT JOIN PostLinks PL_Duplicate ON P.Id = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3
    GROUP BY P.Id
),
PopularTagStats AS (
    -- Identifies tags that are popular based on high-scoring questions in a recent period.
    SELECT
        TagName_unnested AS Tag,
        COUNT(DISTINCT P.Id) AS NumberOfHighScoreQuestions,
        SUM(P.Score) AS TotalScoreOfHighScoreQuestions,
        RANK() OVER (ORDER BY COUNT(DISTINCT P.Id) DESC, SUM(P.Score) DESC) AS TagPopularityRank
    FROM Posts P
    JOIN LATERAL UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags) - 2), '><')) AS TagName_unnested ON TRUE
    WHERE P.PostTypeId = 1 AND P.Score > 50 AND P.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY TagName_unnested
    HAVING COUNT(DISTINCT P.Id) >= 5 -- Only consider tags with at least 5 high-score questions.
)
-- Main query to combine all the derived information and apply final filtering and categorization.
SELECT
    UES.DisplayName,
    UES.Reputation,
    UES.UserCreationDate,
    UES.TotalQuestionAnswerPosts,
    UES.TotalCommentsMade,
    UES.AvgPostScoreByOwner,
    UES.UserUpDownVoteRatio,
    UES.GoldBadgesCount_Correlated,
    PDA.PostId,
    PDA.PostTypeId,
    PDA.PostCreationDate,
    PDA.PostScore,
    PDA.ViewCount,
    PDA.AnswerCount,
    PDA.CommentCount,
    PDA.FavoriteCount,
    PDA.HoursActiveUntilLastActivity,
    PDA.OwnerCommentsDuringActivePeriod,
    PDA.RankByViewsScore,
    PDA.PreviousPostCreationDate,
    PDA.TagString,
    PDA.LastBodyEditDate,
    PDA.AcceptedVoteDate,
    PCA.PostsVotedToClose,
    PCA.PostsVotedToReopen,
    PCA.DuplicateCloseVotesByMe,
    PCA.CloseReopenProfile,
    LADPI.OutgoingLinkedPostsCount,
    LADPI.OutgoingDuplicateTargetCount,
    LADPI.DuplicateTargetIds,
    LADPI.IncomingLinkedCount,
    -- Match the first tag of the post with popular tags, handling cases of no commas or no tags.
    PTS.TagPopularityRank AS MainTagPopularityRank,
    -- Categorize posts based on complex conditions involving multiple attributes.
    CASE
        WHEN PDA.PostTypeId = 1 AND PDA.PostScore > 100 AND PDA.ViewCount > 50000 AND PDA.AnswerCount > 10 THEN 'Viral Question'
        WHEN PDA.PostTypeId = 2 AND PDA.PostScore > 50 AND PDA.OwnerCommentsDuringActivePeriod = 0 AND PDA.LastBodyEditDate IS NULL THEN 'High-Quality "Set-and-Forget" Answer'
        WHEN PDA.PostClosedDate > PDA.PostCreationDate AND PDA.PostClosedDate != '1900-01-01'::timestamp THEN 'Closed Post'
        WHEN PDA.AcceptedVoteDate IS NULL AND PDA.PostTypeId = 1 AND PDA.AnswerCount > 0 THEN 'Unaccepted Question with Answers'
        ELSE 'Other Post Status'
    END AS PostStatusClassification,
    -- Generate an abbreviated user display name, handling NULLs gracefully.
    COALESCE(UPPER(SUBSTRING(UES.DisplayName, 1, 1)) || '_' || LOWER(SUBSTRING(UES.DisplayName, LENGTH(UES.DisplayName) - 2, 3)), 'UNKNOWN_USER') AS UserDisplayNameAbbr,
    -- Correlated subquery to calculate the average score of comments made by others on the post.
    (SELECT AVG(Score) FROM Comments WHERE PostId = PDA.PostId AND CreationDate > PDA.PostCreationDate AND UserId <> PDA.OwnerUserId) AS AvgCommentScoreFromOthers,
    -- A final complex calculation combining user reputation, post quality, and comment activity.
    (UES.Reputation * COALESCE(PDA.PostScore, 0) / GREATEST(1, PDA.ViewCount)) + (UES.TotalCommentsMade * 0.5) AS EngagementInfluenceMetric
FROM UserEngagementSummary UES
INNER JOIN PostDetailsAndActivity PDA ON UES.UserId = PDA.OwnerUserId
LEFT JOIN PostClosingAnalysis PCA ON UES.UserId = PCA.UserId
LEFT JOIN LinkedAndDuplicatePostInfo LADPI ON PDA.PostId = LADPI.PostId
LEFT JOIN PopularTagStats PTS ON
    CASE
        WHEN POSITION(',' IN PDA.TagString) > 0 THEN SUBSTRING(PDA.TagString, 1, POSITION(',' IN PDA.TagString) - 1)
        ELSE PDA.TagString
    END = PTS.Tag
WHERE
    UES.TotalQuestionAnswerPosts > 5 -- Require users with at least some posting activity.
    AND PDA.PostScore >= 0 -- Focus on non-negatively scored posts.
    AND PDA.PostCreationDate >= UES.UserCreationDate + INTERVAL '30 days' -- Exclude posts made in the user's very first month.
    AND (
        PDA.TagString ILIKE '%<performance>%' OR PDA.TagString ILIKE '%<optimization>%' -- Filter for posts related to specific topics.
        OR UES.Reputation > 50000 -- Include posts from very high-reputation users regardless of tags.
        OR PCA.CloseReopenProfile = 'Pro-Close Senior User' -- Include posts from users actively involved in closing processes.
    )
ORDER BY
    UES.Reputation DESC,
    PDA.PostScore DESC,
    PDA.PostCreationDate DESC,
    PDA.ViewCount DESC
LIMIT 5000;
