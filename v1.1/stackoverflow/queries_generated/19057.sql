-- {"query": "19057.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3974} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.WebsiteUrl,
        U.Location,
        COUNT(DISTINCT p.Id) AS TotalPostsCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersGiven,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        -- Calculate upvotes received on posts owned by this user
        SUM(COALESCE(PostUpvotes.UpvotesReceived, 0)) AS TotalUpvotesReceivedOnPosts,
        -- Calculate downvotes received on posts owned by this user
        SUM(COALESCE(PostDownvotes.DownvotesReceived, 0)) AS TotalDownvotesReceivedOnPosts,
        U.UpVotes AS TotalUpvotesGivenByUsers, -- From Users table: votes given by this user
        U.DownVotes AS TotalDownvotesGivenByUsers, -- From Users table: votes given by this user
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgesCount,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadgesCount,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadgesCount,
        MAX(p.CreationDate) AS LatestPostDate,
        MAX(c.CreationDate) AS LatestCommentDate,
        MAX(v.CreationDate) AS LatestVoteGivenDate -- Latest vote *given* by the user
    FROM Users AS U
    LEFT JOIN Posts AS p ON U.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON U.Id = c.UserId
    LEFT JOIN Votes AS v ON U.Id = v.UserId -- Votes made by the user
    -- Correlated subquery (aggregated) to get upvotes received per post, then joined back
    LEFT JOIN (
        SELECT PostId, COUNT(Id) AS UpvotesReceived
        FROM Votes
        WHERE VoteTypeId = 2 -- UpMod
        GROUP BY PostId
    ) AS PostUpvotes ON p.Id = PostUpvotes.PostId
    -- Correlated subquery (aggregated) to get downvotes received per post, then joined back
    LEFT JOIN (
        SELECT PostId, COUNT(Id) AS DownvotesReceived
        FROM Votes
        WHERE VoteTypeId = 3 -- DownMod
        GROUP BY PostId
    ) AS PostDownvotes ON p.Id = PostDownvotes.PostId
    LEFT JOIN Badges AS b ON U.Id = b.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.WebsiteUrl, U.Location, U.UpVotes, U.DownVotes
),
PostDetails AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount, -- Direct use of the column, assuming it is accurate
        P.LastEditDate,
        P.LastActivityDate,
        P.Title,
        P.Body,
        P.ClosedDate,
        COALESCE(P.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        COALESCE(NULLIF(TRIM(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2)), ''), 'no-tags') AS TagsString,
        (
            -- Correlated subquery to find the latest close reason for a post
            SELECT CR.Name
            FROM PostHistory AS PH_CR
            JOIN CloseReasonTypes AS CR ON PH_CR.Comment = CR.Id::varchar(50) -- Cast for potential ID-to-string comparison
            WHERE PH_CR.PostId = P.Id
            AND PH_CR.PostHistoryTypeId = 10 -- Post Closed
            ORDER BY PH_CR.CreationDate DESC
            LIMIT 1
        ) AS LatestCloseReason,
        (
            -- Correlated subquery to count various editing and moderation revisions
            SELECT COUNT(PH_ED.Id)
            FROM PostHistory AS PH_ED
            WHERE PH_ED.PostId = P.Id
            AND PH_ED.PostHistoryTypeId IN (
                4, -- Edit Title
                5, -- Edit Body
                6, -- Edit Tags
                7, 8, 9, -- Rollback operations
                11, -- Post Reopened
                13, -- Post Undeleted
                15, -- Post Unlocked
                20, -- Question Unprotected
                22, -- Question Unmerged
                24  -- Suggested Edit Applied
            )
        ) AS TotalEditRevisions,
        (
            -- Correlated subquery to find the latest comment creation date
            SELECT MAX(C.CreationDate)
            FROM Comments AS C
            WHERE C.PostId = P.Id
        ) AS LastCommentDate,
        (
            -- Correlated subquery to calculate the average score of comments on this post
            SELECT AVG(C.Score)
            FROM Comments AS C
            WHERE C.PostId = P.Id
        ) AS AverageCommentScore,
        COALESCE(P.ParentId, -1) AS ParentPostId
    FROM Posts AS P
    JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
),
FlattenedTags AS (
    SELECT
        PD.PostId,
        PD.OwnerUserId,
        PD.PostTypeId,
        TRIM(tag_unnested.tag) AS TagName
    FROM PostDetails AS PD
    CROSS JOIN LATERAL UNNEST(string_to_array(PD.TagsString, '><')) AS tag_unnested(tag)
    WHERE PD.TagsString <> 'no-tags' AND PD.TagsString IS NOT NULL
),
UserTagContributions AS (
    SELECT
        FT.OwnerUserId AS UserId,
        FT.TagName,
        COUNT(FT.PostId) AS PostsInTag,
        SUM(PD.PostScore) AS TotalScoreInTag,
        AVG(PD.PostScore) AS AvgScoreInTag,
        DENSE_RANK() OVER (PARTITION BY FT.OwnerUserId ORDER BY COUNT(FT.PostId) DESC, SUM(PD.PostScore) DESC) AS TagRank
    FROM FlattenedTags AS FT
    JOIN PostDetails AS PD ON FT.PostId = PD.PostId
    GROUP BY
        FT.OwnerUserId, FT.TagName
),
AggregatedPostMetrics AS (
    SELECT
        PD.OwnerUserId AS UserId,
        SUM(PD.PostScore) AS TotalPostScore,
        AVG(PD.PostScore) AS AveragePostScore,
        AVG(PD.ViewCount) AS AverageViewCount,
        SUM(CASE WHEN PD.PostTypeId = 1 THEN PD.AnswerCount ELSE 0 END) AS TotalAnswersOnQuestions,
        SUM(CASE WHEN PD.PostTypeId = 1 AND PD.AcceptedAnswerId IS NOT NULL AND PD.AcceptedAnswerId <> -1 THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
        SUM(CASE WHEN PD.PostTypeId = 2 AND PD.PostId = P_PARENT.AcceptedAnswerId THEN 1 ELSE 0 END) AS AnswersAcceptedByOthers,
        SUM(PD.CommentCount) AS TotalCommentsOnPosts,
        SUM(PD.FavoriteCount) AS TotalFavoritesOnPosts,
        MAX(PD.TotalEditRevisions) AS MaxEditsOnAnyPost,
        AVG(PD.AverageCommentScore) FILTER (WHERE PD.PostTypeId IN (1,2) AND PD.AverageCommentScore IS NOT NULL) AS AvgCommentScoreOnQandA,
        -- Average time difference in days from last activity (either post edit or comment) until now
        AVG(EXTRACT(EPOCH FROM (NOW() - COALESCE(PD.LastActivityDate, PD.PostCreationDate))) / 86400) AS AvgDaysSinceLastActivity
    FROM PostDetails AS PD
    LEFT JOIN Posts AS P_PARENT ON PD.ParentPostId = P_PARENT.Id
    GROUP BY PD.OwnerUserId
),
UserPerformanceScores AS (
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        UAS.Reputation,
        UAS.LastAccessDate,
        UAS.TotalPostsCount,
        UAS.TotalQuestionsAsked,
        UAS.TotalAnswersGiven,
        APM.TotalPostScore,
        APM.AveragePostScore,
        APM.AverageViewCount,
        APM.QuestionsWithAcceptedAnswers,
        APM.AnswersAcceptedByOthers,
        APM.TotalCommentsOnPosts,
        UAS.TotalUpvotesReceivedOnPosts,
        UAS.TotalDownvotesReceivedOnPosts,
        UAS.TotalUpvotesGivenByUsers,
        UAS.TotalDownvotesGivenByUsers,
        UAS.GoldBadgesCount,
        UAS.SilverBadgesCount,
        UAS.BronzeBadgesCount,
        UT.TagName AS TopContributingTag,
        UT.PostsInTag AS TopTagPostsCount,
        UT.TotalScoreInTag AS TopTagTotalScore,
        UAS.WebsiteUrl,
        UAS.Location,
        (
            -- Weighted sum for engagement: Reputation, Posts, Upvotes received, Accepted Answers, Badges
            (UAS.Reputation * 0.15) +
            (UAS.TotalPostsCount * 0.5) +
            (UAS.TotalUpvotesReceivedOnPosts * 0.8) +
            (UAS.AnswersAcceptedByOthers * 1.2) +
            (UAS.GoldBadgesCount * 5.0) +
            (UAS.SilverBadgesCount * 2.0) +
            (UAS.BronzeBadgesCount * 0.5) -
            (UAS.TotalDownvotesReceivedOnPosts * 0.4) - -- Penalize for downvotes received
            (UAS.TotalDownvotesGivenByUsers * 0.1) -- Slight penalty for giving too many downvotes
        ) AS RawEngagementScore,
        (
            -- Weighted sum for content quality and influence: Accepted Answers by user's questions, Average Score, View Count, Comment Score
            (COALESCE(APM.QuestionsWithAcceptedAnswers, 0) * 2.0) +
            (COALESCE(APM.TotalAnswersOnQuestions, 0) * 0.5) +
            (COALESCE(APM.AveragePostScore, 0) * 0.1) +
            (COALESCE(APM.AverageViewCount, 0) * 0.01) +
            (COALESCE(APM.AvgCommentScoreOnQandA, 0) * 0.5)
            -- Penalize for low quality questions, e.g. those that are closed
            - (SELECT COUNT(PD_Closed.PostId) FROM PostDetails PD_Closed WHERE PD_Closed.OwnerUserId = UAS.UserId AND PD_Closed.LatestCloseReason IS NOT NULL) * 0.75
        ) AS RawInfluenceScore,
        DATE_TRUNC('month', UAS.UserCreationDate) AS UserCreationMonth
    FROM UserActivitySummary AS UAS
    LEFT JOIN AggregatedPostMetrics AS APM ON UAS.UserId = APM.UserId
    LEFT JOIN UserTagContributions AS UT ON UAS.UserId = UT.UserId AND UT.TagRank = 1
    WHERE UAS.TotalPostsCount > 0 OR UAS.TotalCommentsMade > 0 -- Filter out truly inactive users
)
SELECT
    UPS.UserId,
    COALESCE(UPS.DisplayName, 'Anonymous User #' || UPS.UserId::varchar) AS UserDisplayName,
    UPS.Reputation,
    UPS.TotalPostsCount,
    UPS.TotalQuestionsAsked,
    UPS.TotalAnswersGiven,
    UPS.TotalUpvotesReceivedOnPosts,
    UPS.TotalDownvotesGivenByUsers,
    UPS.QuestionsWithAcceptedAnswers,
    UPS.AnswersAcceptedByOthers,
    UPS.GoldBadgesCount,
    UPS.SilverBadgesCount,
    UPS.BronzeBadgesCount,
    COALESCE(UPS.TopContributingTag, 'unspecified') AS TopContributingTag,
    COALESCE(UPS.TopTagPostsCount, 0) AS TopTagPostsCount,
    COALESCE(UPS.TopTagTotalScore, 0) AS TopTagTotalScore,
    ROUND(UPS.RawEngagementScore::numeric, 2) AS EngagementScore,
    ROUND(UPS.RawInfluenceScore::numeric, 2) AS InfluenceScore,
    ROUND((UPS.RawEngagementScore + UPS.RawInfluenceScore)::numeric / 2, 2) AS OverallUserPerformance,
    DENSE_RANK() OVER (ORDER BY (UPS.RawEngagementScore + UPS.RawInfluenceScore) DESC, UPS.Reputation DESC, UPS.LastAccessDate DESC) AS OverallRank,
    NTILE(10) OVER (ORDER BY (UPS.RawEngagementScore + UPS.RawInfluenceScore) DESC) AS PerformanceDecile,
    LAG(UPS.Reputation, 1, 0) OVER (ORDER BY (UPS.RawEngagementScore + UPS.RawInfluenceScore) DESC) AS PreviousRankedUserReputation,
    LEAD(UPS.Reputation, 1, 0) OVER (ORDER BY (UPS.RawEngagementScore + UPS.RawInfluenceScore) DESC) AS NextRankedUserReputation,
    MAX(UPS.LastAccessDate) OVER (PARTITION BY UPS.UserCreationMonth) AS LastAccessDateForMonthGroup,
    (
        -- Correlated subquery: Count unique posts linked *from* this user's posts
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks AS pl
        WHERE pl.PostId IN (SELECT PD.PostId FROM PostDetails PD WHERE PD.OwnerUserId = UPS.UserId)
        AND pl.LinkTypeId = 1 -- Linked
    ) AS UniqueLinkedPostsCount,
    (
        -- Correlated subquery: Count unique posts this user's posts are marked as duplicates *of*
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks AS pl
        WHERE pl.PostId IN (SELECT PD.PostId FROM PostDetails PD WHERE PD.OwnerUserId = UPS.UserId)
        AND pl.LinkTypeId = 3 -- Duplicate
    ) AS UniqueDuplicateLinksMadeCount,
    -- Array aggregate top 5 question IDs by score for this user
    ARRAY_AGG(DISTINCT PD_TopPosts.PostId ORDER BY PD_TopPosts.PostScore DESC, PD_TopPosts.ViewCount DESC) FILTER (WHERE PD_TopPosts.PostTypeId = 1) AS TopQuestionIdsByScore,
    -- Array aggregate top 5 answer IDs by score for this user
    ARRAY_AGG(DISTINCT PD_TopPosts.PostId ORDER BY PD_TopPosts.PostScore DESC, PD_TopPosts.ViewCount DESC) FILTER (WHERE PD_TopPosts.PostTypeId = 2) AS TopAnswerIdsByScore,
    (CURRENT_DATE - UPS.LastAccessDate::date) AS DaysSinceLastAccess,
    COALESCE(UPS.WebsiteUrl, 'N/A') AS UserWebsiteUrl,
    COALESCE(UPS.Location, 'Unknown') AS UserLocation,
    CASE
        WHEN (CURRENT_DATE - UPS.LastAccessDate::date) < 30 THEN 'Highly Active'
        WHEN (CURRENT_DATE - UPS.LastAccessDate::date) < 180 THEN 'Moderately Active'
        ELSE 'Less Active'
    END AS UserActivityStatus,
    -- Example of complex predicate/expression with string and null logic
    NULLIF(MD5(CONCAT(UPS.DisplayName, UPS.UserId, UPS.UserCreationDate::varchar)), 'd41d8cd98f00b204e9800998ecf8427e') AS UserIdentifierHash -- Exclude empty hash
FROM UserPerformanceScores AS UPS
LEFT JOIN PostDetails AS PD_TopPosts ON UPS.UserId = PD_TopPosts.OwnerUserId
GROUP BY
    UPS.UserId, UPS.DisplayName, UPS.Reputation, UPS.LastAccessDate, UPS.TotalPostsCount,
    UPS.TotalQuestionsAsked, UPS.TotalAnswersGiven, UPS.TotalPostScore, UPS.AveragePostScore,
    UPS.AverageViewCount, UPS.QuestionsWithAcceptedAnswers, UPS.AnswersAcceptedByOthers,
    UPS.TotalCommentsOnPosts, UPS.TotalUpvotesReceivedOnPosts, UPS.TotalDownvotesGivenByUsers,
    UPS.GoldBadgesCount, UPS.SilverBadgesCount, UPS.BronzeBadgesCount, UPS.TopContributingTag,
    UPS.TopTagPostsCount, UPS.TopTagTotalScore, UPS.RawEngagementScore, UPS.RawInfluenceScore,
    UPS.UserCreationMonth, UPS.WebsiteUrl, UPS.Location
HAVING UPS.TotalPostsCount > 5 AND UPS.Reputation > 100 -- Minimum activity/reputation threshold
ORDER BY OverallRank ASC, EngagementScore DESC
LIMIT 100;
