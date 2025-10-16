-- {"query": "19093.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3858} 

WITH UserEngagementSummary AS (
    -- Aggregate primary user engagement metrics: posts, comments, badges, and votes cast/received
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        COALESCE(U.Views, 0) AS UserProfileViews,
        COALESCE(U.UpVotes, 0) AS UserUpvotesReceived,
        COALESCE(U.DownVotes, 0) AS UserDownvotesReceived,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersSubmitted,
        SUM(P.Score) FILTER (WHERE P.PostTypeId IN (1, 2)) AS TotalContentScore,
        COALESCE(MAX(P.LastActivityDate), U.CreationDate) AS LatestPostActivity,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN V.VoteTypeId = 2 AND V.UserId = U.Id THEN 1 ELSE 0 END) AS UpvotesCast,
        SUM(CASE WHEN V.VoteTypeId = 3 AND V.UserId = U.Id THEN 1 ELSE 0 END) AS DownvotesCast,
        SUM(CASE WHEN P.AcceptedAnswerId = P.Id AND P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AcceptedAnswersCount
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    LEFT JOIN Votes AS V ON U.Id = V.UserId -- Votes cast by the user
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostTagUnnest AS (
    -- Extract individual tags from Posts.Tags field for analysis, focusing on questions.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate,
        P.Score,
        P.Title,
        P.Tags,
        TRIM(unnest(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts AS P
    WHERE P.Tags IS NOT NULL AND P.PostTypeId = 1 -- Only questions commonly have user-defined tags
),
GlobalTagPopularity AS (
    -- Calculate global popularity and rank of tags based on post count and total score
    SELECT
        TagName,
        COUNT(DISTINCT PostId) AS TaggedPostsCount,
        SUM(Score) AS TotalTagScore,
        AVG(Score) AS AvgTagScore,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT PostId) DESC, SUM(Score) DESC) AS TagGlobalRank
    FROM PostTagUnnest
    GROUP BY TagName
    HAVING COUNT(DISTINCT PostId) > 50 -- Filter out less popular tags for global analysis
),
UserFirstPostHistory AS (
    -- Identify the very first post of each user and extract key history details like initial content, latest edit, and close events
    SELECT
        U.Id AS UserId,
        P.Id AS FirstPostId,
        P.CreationDate AS FirstPostCreationDate,
        P.PostTypeId AS FirstPostTypeId,
        (SELECT PH_init.Text FROM PostHistory PH_init WHERE PH_init.PostId = P.Id AND PH_init.PostHistoryTypeId IN (1,2) ORDER BY PH_init.CreationDate ASC LIMIT 1) AS InitialBodyOrTitle,
        (SELECT PH_latest.Text FROM PostHistory PH_latest WHERE PH_latest.PostId = P.Id AND PH_latest.PostHistoryTypeId IN (4,5) ORDER BY PH_latest.CreationDate DESC LIMIT 1) AS LatestEditedBodyOrTitle,
        (SELECT COUNT(DISTINCT PH_edits.Id) FROM PostHistory PH_edits WHERE PH_edits.PostId = P.Id AND PH_edits.PostHistoryTypeId IN (4,5,6,8,9)) AS EditCount,
        (SELECT MAX(PH_closed.Comment) FROM PostHistory PH_closed WHERE PH_closed.PostId = P.Id AND PH_closed.PostHistoryTypeId = 10 AND PH_closed.Comment IS NOT NULL) AS LastCloseReasonIdString,
        (SELECT COUNT(DISTINCT PH_closed.Id) FROM PostHistory PH_closed WHERE PH_closed.PostId = P.Id AND PH_closed.PostHistoryTypeId = 10) AS CloseEventCount
    FROM Users AS U
    LEFT JOIN LATERAL ( -- Use LATERAL join to efficiently find the first post for each user
        SELECT Id, CreationDate, PostTypeId
        FROM Posts
        WHERE OwnerUserId = U.Id
        ORDER BY CreationDate ASC
        LIMIT 1
    ) AS P ON TRUE
    WHERE P.Id IS NOT NULL
),
PostLinkAggregates AS (
    -- Aggregate link counts and scores for all posts, grouped by their owner for user-level link network analysis
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT PL_Out.RelatedPostId) AS TotalOutgoingLinkCount,
        COUNT(DISTINCT PL_In.PostId) AS TotalIncomingLinkCount,
        SUM(COALESCE(P_Linked.Score, 0)) AS SumScoreOfLinkedPosts,
        SUM(COALESCE(P_Related.Score, 0)) AS SumScoreOfLinkingPosts
    FROM Posts AS P
    LEFT JOIN PostLinks AS PL_Out ON P.Id = PL_Out.PostId
    LEFT JOIN Posts AS P_Linked ON PL_Out.RelatedPostId = P_Linked.Id
    LEFT JOIN PostLinks AS PL_In ON P.Id = PL_In.RelatedPostId
    LEFT JOIN Posts AS P_Related ON PL_In.PostId = P_Related.Id
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
)
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    NTILE(10) OVER (ORDER BY UES.Reputation DESC) AS ReputationDecile, -- Assign users to reputation deciles (window function)
    UES.UserProfileViews,
    UES.UserUpvotesReceived,
    UES.UserDownvotesReceived,
    UES.TotalPostsCreated,
    UES.QuestionsAsked,
    UES.AnswersSubmitted,
    UES.TotalContentScore,
    UES.TotalBadges,
    UES.GoldBadges,
    UES.SilverBadges,
    UES.BronzeBadges,
    UES.UpvotesCast,
    UES.DownvotesCast,
    UES.AcceptedAnswersCount,
    -- User's top tag based on their own posts, and its global popularity rank
    TOP_USER_TAG.TagName AS UserTopTagName,
    TOP_USER_TAG.TaggedPostsCount AS UserTopTagPosts,
    TOP_USER_TAG.TotalTagScore AS UserTopTagScore,
    GTP_UserTop.TagGlobalRank AS UserTopTagGlobalRank,
    -- String aggregation for a semicolon-separated list of globally top-ranked tags used by the user
    STRING_AGG(DISTINCT PTA_Agg.TagName, '; ') FILTER (WHERE GTP_Agg.TagGlobalRank <= 10) AS Top10GlobalTagsUsedByThisUser,
    -- Detailed analysis of the user's very first post
    UFPH.FirstPostId,
    UFPH.FirstPostCreationDate,
    UFPH.FirstPostTypeId,
    COALESCE(LENGTH(UFPH.InitialBodyOrTitle), 0) AS InitialContentLength_FirstPost,
    COALESCE(LENGTH(UFPH.LatestEditedBodyOrTitle), 0) AS LatestContentLength_FirstPost,
    UFPH.EditCount AS EditCount_FirstPost,
    UFPH.CloseEventCount AS CloseEventCount_FirstPost,
    CR.Name AS LastCloseReason_FirstPost,
    CASE -- Complex conditional logic to categorize the edit status of the first post
        WHEN UFPH.InitialBodyOrTitle IS NOT NULL AND UFPH.LatestEditedBodyOrTitle IS NOT NULL AND LENGTH(UFPH.InitialBodyOrTitle) <> LENGTH(UFPH.LatestEditedBodyOrTitle) THEN 'ContentLengthChanged'
        WHEN UFPH.InitialBodyOrTitle IS NOT NULL AND UFPH.LatestEditedBodyOrTitle IS NULL AND UFPH.EditCount > 0 THEN 'EditedButNoLatestContent'
        WHEN UFPH.InitialBodyOrTitle IS NULL AND UFPH.LatestEditedBodyOrTitle IS NOT NULL THEN 'NoInitialContentButHasEdited'
        WHEN UFPH.EditCount = 0 THEN 'NoEdits'
        ELSE 'StatusUndetermined'
    END AS FirstPostEditStatusDetail,
    -- Aggregated link network statistics for all posts owned by the user
    COALESCE(PLA.TotalOutgoingLinkCount, 0) AS TotalOutgoingLinksFromUserPosts,
    COALESCE(PLA.TotalIncomingLinkCount, 0) AS TotalIncomingLinksToUserPosts,
    COALESCE(PLA.SumScoreOfLinkedPosts, 0) AS TotalScoreOfPostsLinkedFromUserPosts,
    COALESCE(PLA.SumScoreOfLinkingPosts, 0) AS TotalScoreOfPostsLinkingToUserPosts,
    -- Date and time calculations using AGE() and EXTRACT()
    EXTRACT(DAY FROM AGE(UES.LastAccessDate, UES.CreationDate)) AS DaysActiveSinceCreation,
    COALESCE(EXTRACT(YEAR FROM AGE(NOW(), UES.CreationDate)), 0) AS AccountAgeYears,
    -- NULL logic and string expressions
    COALESCE(UES.DisplayName, 'UNKNOWN USER') AS DisplayNameOrDefault,
    NULLIF(TRIM(U.AboutMe), '') IS NOT NULL AS HasAboutMeContent, -- Check for non-empty AboutMe
    -- Correlated subquery: Average score of accepted answers for user's questions posted in the last 2 years
    (
        SELECT AVG(Ans.Score)
        FROM Posts AS Q
        JOIN Posts AS Ans ON Q.AcceptedAnswerId = Ans.Id
        WHERE Q.OwnerUserId = UES.UserId
          AND Q.PostTypeId = 1
          AND Ans.PostTypeId = 2
          AND Q.CreationDate >= (NOW() - INTERVAL '2 year')
    ) AS AvgAcceptedAnswerScoreOnRecentQuestions,
    -- Correlated subquery: Percentage of comments with a positive score on any of the user's posts
    (
        SELECT
            ROUND(
                CAST(COUNT(CASE WHEN C.Score > 0 THEN C.Id END) AS NUMERIC) * 100 /
                NULLIF(COUNT(C.Id), 0), 2
            )
        FROM Comments AS C
        JOIN Posts P_UserOwned ON C.PostId = P_UserOwned.Id
        WHERE P_UserOwned.OwnerUserId = UES.UserId
          AND C.CreationDate BETWEEN UES.CreationDate AND UES.LastAccessDate
    ) AS PctPositiveCommentsOnUserPosts,
    -- Correlated subquery: Total number of posts favorited by this specific user
    (SELECT COUNT(DISTINCT V.PostId) FROM Votes V WHERE V.UserId = UES.UserId AND V.VoteTypeId = 5) AS TotalFavoritePostsByUser,
    -- Correlated subquery: Total number of times *this user's posts* have been favorited by *other users*
    (SELECT COUNT(DISTINCT V_Fav.UserId) FROM Votes V_Fav JOIN Posts P_Fav_User ON V_Fav.PostId = P_Fav_User.Id WHERE P_Fav_User.OwnerUserId = UES.UserId AND V_Fav.VoteTypeId = 5) AS UserPostsFavoritedByOthersCount,
    -- Average length of tags used by the user for their questions
    (SELECT AVG(LENGTH(T_Inner.TagName)) FROM PostTagUnnest T_Inner WHERE T_Inner.OwnerUserId = UES.UserId) AS AvgTagLengthForUser,
    -- Complex string manipulation: Capitalize first letter, lowercase rest, and replace all vowels with '*'
    COALESCE(
        REGEXP_REPLACE(
            UPPER(SUBSTRING(UES.DisplayName FROM 1 FOR 1)) ||
            LOWER(SUBSTRING(UES.DisplayName FROM 2)),
            '[AEIOUaeiou]', -- Matches both uppercase and lowercase vowels
            '*',
            'g' -- Global replacement
        ),
        'UNKNOWN_MASKED'
    ) AS FormattedAndMaskedDisplayName,
    -- Conditional aggregation using a window function for an 'Engagement Level Score'
    SUM(CASE
        WHEN UES.Reputation > 10000 AND UES.QuestionsAsked > 100 THEN 5 -- Highly reputable questioner
        WHEN UES.Reputation > 5000 AND UES.AnswersSubmitted > 200 THEN 4 -- Expert answerer
        WHEN UES.TotalBadges >= 10 AND UES.TotalContentScore > 1000 THEN 3 -- Engaged community member
        WHEN UES.TotalPostsCreated > 50 THEN 2 -- Regular contributor
        ELSE 1 -- Basic participant
    END) OVER (PARTITION BY UES.ReputationDecile) AS EngagementLevelScoreByDecile
FROM UserEngagementSummary AS UES
JOIN Users AS U ON UES.UserId = U.Id -- Re-join Users for accessing the AboutMe text field
LEFT JOIN LATERAL ( -- Lateral join to find the single top tag for each user
    SELECT
        PTU.TagName,
        COUNT(PTU.PostId) AS TaggedPostsCount,
        SUM(PTU.Score) AS TotalTagScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(PTU.PostId) DESC, SUM(PTU.Score) DESC) AS UserTagRank
    FROM PostTagUnnest AS PTU
    WHERE PTU.OwnerUserId = UES.UserId
    GROUP BY PTU.TagName
    ORDER BY UserTagRank ASC
    LIMIT 1
) AS TOP_USER_TAG ON TRUE
LEFT JOIN GlobalTagPopularity AS GTP_UserTop ON TOP_USER_TAG.TagName = GTP_UserTop.TagName
LEFT JOIN PostTagUnnest AS PTA_Agg ON PTA_Agg.OwnerUserId = UES.UserId -- For aggregating lists of tags
LEFT JOIN GlobalTagPopularity AS GTP_Agg ON PTA_Agg.TagName = GTP_Agg.TagName
LEFT JOIN UserFirstPostHistory AS UFPH ON UES.UserId = UFPH.UserId
LEFT JOIN CloseReasonTypes AS CR ON CR.Id = NULLIF(UFPH.LastCloseReasonIdString, '')::smallint -- Convert string ID to smallint
LEFT JOIN PostLinkAggregates AS PLA ON PLA.UserId = UES.UserId
WHERE UES.TotalPostsCreated >= 10 AND UES.Reputation >= 500 -- Filter for active and moderately reputable users
GROUP BY
    UES.UserId, UES.DisplayName, UES.Reputation, UES.UserProfileViews, UES.UserUpvotesReceived, UES.UserDownvotesReceived,
    UES.TotalPostsCreated, UES.QuestionsAsked, UES.AnswersSubmitted, UES.TotalContentScore, UES.TotalBadges,
    UES.GoldBadges, UES.SilverBadges, UES.BronzeBadges, UES.UpvotesCast, UES.DownvotesCast, UES.AcceptedAnswersCount,
    TOP_USER_TAG.TagName, TOP_USER_TAG.TaggedPostsCount, TOP_USER_TAG.TotalTagScore, GTP_UserTop.TagGlobalRank,
    UFPH.FirstPostId, UFPH.FirstPostCreationDate, UFPH.FirstPostTypeId, UFPH.InitialBodyOrTitle, UFPH.LatestEditedBodyOrTitle,
    UFPH.EditCount, UFPH.CloseEventCount, CR.Name, U.AboutMe, UES.CreationDate, UES.LastAccessDate,
    PLA.TotalOutgoingLinkCount, PLA.TotalIncomingLinkCount, PLA.SumScoreOfLinkedPosts, PLA.SumScoreOfLinkingPosts
ORDER BY UES.Reputation DESC, UES.TotalContentScore DESC
LIMIT 1000;
