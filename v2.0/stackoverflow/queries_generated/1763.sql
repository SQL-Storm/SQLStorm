-- {"query": "1763.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4281} 

WITH UserActivitySummary AS (
    -- Gathers comprehensive activity metrics for each user, including post counts by type, comment counts,
    -- aggregated vote counts on their posts, and reputation gain rate.
    -- Uses LEFT JOIN to ensure all users are considered, regardless of their activity levels.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS UserTotalUpVotesGiven,
        U.DownVotes AS UserTotalDownVotesGiven,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestionsPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswersPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId IN (3,4,5) THEN 1 ELSE 0 END), 0) AS TotalWikiPosts,
        COALESCE(COUNT(DISTINCT P.Id), 0) AS TotalPostsCreated,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN PV.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotesReceivedOnPosts,
        COALESCE(SUM(CASE WHEN PV.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotesReceivedOnPosts,
        COALESCE(SUM(CASE WHEN PV.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS TotalFavoritesReceivedOnPosts,
        COALESCE(AVG(P.Score) FILTER (WHERE P.PostTypeId IN (1,2,3,4,5)), 0.0) AS AvgPostScore,
        CASE
            WHEN (EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60 * 60 * 24)) > 0
            THEN U.Reputation / (EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60 * 60 * 24))
            ELSE 0.0
        END AS RepPerDayActive,
        MAX(P.CreationDate) AS LatestPostDate,
        MAX(C.CreationDate) AS LatestCommentDate,
        MIN(P.CreationDate) AS FirstPostDate
    FROM
        Users AS U
    LEFT JOIN
        Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments AS C ON U.Id = C.UserId
    LEFT JOIN
        Votes AS PV ON P.Id = PV.PostId AND PV.VoteTypeId IN (2,3,5) -- Votes received on user's posts
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
),
PostContentAnalysis AS (
    -- Provides detailed analysis for each post, including status, age, tag counts, and historical events.
    -- Incorporates correlated subqueries for specific counts and average comment scores.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        PT.Name AS PostTypeName,
        P.Title,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer'
            WHEN P.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Open'
        END AS PostStatus,
        EXTRACT(EPOCH FROM (NOW() - P.CreationDate)) / (60 * 60 * 24) AS PostAgeDays,
        ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'), 1) AS NumberOfTags,
        (SELECT PH.UserDisplayName FROM PostHistory AS PH WHERE PH.PostId = P.Id ORDER BY PH.CreationDate DESC LIMIT 1) AS LastEditorDisplayNameFromHistory,
        (SELECT PH.UserId FROM PostHistory AS PH WHERE PH.PostId = P.Id ORDER BY PH.CreationDate DESC LIMIT 1) AS LastEditorUserIdFromHistory,
        (SELECT COUNT(PH.Id) FROM PostHistory AS PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4,5,6,10,11,12,13,19,20)) AS SignificantHistoryEventCount,
        COALESCE((SELECT AVG(C.Score) FROM Comments AS C WHERE C.PostId = P.Id AND C.Score IS NOT NULL), 0.0) AS AvgCommentScore,
        LENGTH(P.Body) / (NULLIF(LENGTH(P.Title), 0) + NULLIF(P.AnswerCount, 0) + NULLIF(P.CommentCount, 0) + 1.0) AS ContentDensityScore -- A measure of detail per interaction
    FROM
        Posts AS P
    JOIN
        PostTypes AS PT ON P.PostTypeId = PT.Id
),
BadgeMetrics AS (
    -- Quantifies the number of gold, silver, and bronze badges per user, and ranks users based on their badge collection.
    SELECT
        U.Id AS UserId,
        COALESCE(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        DENSE_RANK() OVER (ORDER BY COALESCE(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) DESC,
                                    COALESCE(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) DESC,
                                    COALESCE(SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) DESC,
                                    U.Reputation DESC) AS BadgeRank
    FROM
        Users AS U
    LEFT JOIN
        Badges AS B ON U.Id = B.UserId
    GROUP BY
        U.Id
),
PostCollaborationMetrics AS (
    -- Tracks relationships between posts (linked, duplicate) and the users involved, calculating time differences.
    SELECT
        PL.PostId,
        PL.RelatedPostId,
        PL.LinkTypeId,
        LT.Name AS LinkTypeName,
        P1.OwnerUserId AS SourceOwnerUserId,
        P2.OwnerUserId AS RelatedOwnerUserId,
        P1.CreationDate AS SourcePostCreationDate,
        P2.CreationDate AS RelatedPostCreationDate,
        ABS(EXTRACT(EPOCH FROM (P1.CreationDate - P2.CreationDate)) / (60 * 60 * 24)) AS DaysBetweenLinkedPosts
    FROM
        PostLinks AS PL
    JOIN
        LinkTypes AS LT ON PL.LinkTypeId = LT.Id
    JOIN
        Posts AS P1 ON PL.PostId = P1.Id
    JOIN
        Posts AS P2 ON PL.RelatedPostId = P2.Id
),
TrendingTags AS (
    -- Identifies tags that are currently trending based on recent high-scoring and highly-viewed questions.
    -- Uses fuzzy matching for tag in the tags string for performance benchmarking.
    SELECT
        Tag.TagName,
        COUNT(DISTINCT P.Id) AS PostsWithTagCount,
        SUM(P.ViewCount) AS TotalTagViewCount,
        AVG(P.Score) AS AvgTagPostScore,
        DENSE_RANK() OVER (ORDER BY SUM(P.ViewCount) DESC, COUNT(DISTINCT P.Id) DESC, AVG(P.Score) DESC) AS TagViewRank
    FROM
        Tags AS Tag
    JOIN
        Posts AS P ON P.Tags LIKE CONCAT('%<', Tag.TagName, '>%')
    WHERE
        P.CreationDate >= NOW() - INTERVAL '6 months' AND P.PostTypeId = 1 AND P.Score > 5
    GROUP BY
        Tag.TagName
    HAVING
        COUNT(DISTINCT P.Id) > 5 AND SUM(P.ViewCount) > 1000
)
-- Main query: Combines user activity, post details, badge information, and trending topics.
-- It generates two sets of results using UNION ALL: one for established influential users/posts,
-- and another for emerging contributors.
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserCreationDate,
    UAS.TotalQuestionsPosted,
    UAS.TotalAnswersPosted,
    UAS.TotalPostsCreated,
    UAS.TotalCommentsMade,
    UAS.AvgPostScore,
    BM.GoldBadges,
    BM.SilverBadges,
    BM.BronzeBadges,
    BM.BadgeRank,
    PCA.PostId,
    PCA.PostTypeName,
    PCA.Title,
    PCA.Score AS PostScore,
    PCA.ViewCount AS PostViewCount,
    PCA.PostAgeDays,
    PCA.PostStatus,
    PCA.NumberOfTags,
    PCA.SignificantHistoryEventCount,
    PCA.AvgCommentScore,
    PCA.ContentDensityScore,
    T.TagName AS PrimaryTrendingTag,
    T.TotalTagViewCount AS PrimaryTrendingTagViews,
    T.AvgTagPostScore AS PrimaryTrendingTagAvgScore,
    -- Window function: Average Reputation of users within the same badge rank
    AVG(UAS.Reputation) OVER (PARTITION BY BM.BadgeRank) AS AvgReputationInBadgeRank,
    -- Window function: Cumulative sum of posts by user over time, ordered by post creation date
    COUNT(PCA.PostId) OVER (PARTITION BY UAS.UserId ORDER BY PCA.PostCreationDate) AS CumulativePostsByDate,
    CAST(UAS.TotalQuestionsPosted AS NUMERIC) / NULLIF(UAS.TotalPostsCreated, 0) AS PercentQuestions,
    -- Categorizes users based on a combination of reputation, badges, and post quality.
    CASE
        WHEN UAS.Reputation > 20000 AND BM.GoldBadges >= 10 AND UAS.AvgPostScore > 15 THEN 'Highly Influential Veteran'
        WHEN UAS.Reputation > 5000 AND UAS.TotalPostsCreated > 150 AND UAS.RepPerDayActive > 7 THEN 'Prolific Active Contributor'
        WHEN PCA.PostId IS NOT NULL AND PCA.PostStatus = 'Accepted Answer' AND PCA.Score > 75 THEN 'High-Quality Content Creator'
        WHEN UAS.AvgPostScore IS NULL OR UAS.AvgPostScore = 0 THEN 'Non-Post User'
        ELSE 'General Contributor'
    END AS UserInfluenceCategory,
    -- Complex string expression: Concatenates post status, truncated title, and up to 3 primary tags.
    CONCAT_WS(' | ',
        PCA.PostStatus,
        SUBSTRING(COALESCE(PCA.Title, 'No Title'), 1, 40),
        ARRAY_TO_STRING((SELECT ARRAY_AGG(tag_val) FROM (SELECT tag_val FROM UNNEST(string_to_array(SUBSTRING(PCA.Tags, 2, LENGTH(PCA.Tags) - 2), '><')) AS tag_val ORDER BY 1 LIMIT 3) AS limited_tags), ', ')
    ) AS PostSummaryInfo,
    -- Calculates an engagement score based on favorites, comments, and answers, with NULL handling.
    COALESCE(PCA.FavoriteCount, 0) + (COALESCE(PCA.CommentCount, 0) * 0.75) + (COALESCE(PCA.AnswerCount, 0) * 2.5) AS EngagementScore,
    -- Correlated subquery to count posts where the user was involved in a collaboration (linking/duplication).
    (SELECT COUNT(DISTINCT PCM.RelatedPostId) FROM PostCollaborationMetrics AS PCM WHERE PCM.SourceOwnerUserId = UAS.UserId OR PCM.RelatedOwnerUserId = UAS.UserId) AS CollaboratedPostsCount
FROM
    UserActivitySummary AS UAS
LEFT JOIN
    BadgeMetrics AS BM ON UAS.UserId = BM.UserId
LEFT JOIN
    PostContentAnalysis AS PCA ON UAS.UserId = PCA.OwnerUserId
LEFT JOIN LATERAL ( -- LATERAL join to find the single most relevant trending tag for a post
    SELECT TT.TagName, TT.TotalTagViewCount, TT.AvgTagPostScore
    FROM TrendingTags AS TT
    WHERE PCA.Tags LIKE CONCAT('%<', TT.TagName, '>%')
    ORDER BY TT.TotalTagViewCount DESC, TT.AvgTagPostScore DESC
    LIMIT 1
) AS T ON TRUE
WHERE
    UAS.Reputation > 5000 -- Filter for established users
    AND (
        UAS.TotalPostsCreated > 75 -- Either many posts
        OR UAS.TotalCommentsMade > 150 -- Or many comments
        OR (BM.GoldBadges > 0 AND UAS.AvgPostScore > 7.5) -- Or high quality content (gold badge + avg score)
    )
    AND PCA.PostId IS NOT NULL -- Ensure a post is associated
    AND NOT EXISTS ( -- Exclude users who have had a significant percentage of their *own* posts deleted
        SELECT 1
        FROM Posts AS P_deleted
        JOIN PostHistory AS PH_deleted ON P_deleted.Id = PH_deleted.PostId
        WHERE P_deleted.OwnerUserId = UAS.UserId
          AND PH_deleted.PostHistoryTypeId = 12 -- Post Deleted
        GROUP BY P_deleted.OwnerUserId
        HAVING COUNT(DISTINCT P_deleted.Id) > (UAS.TotalPostsCreated * 0.15)
    )
    -- Complex predicate combining date and numerical conditions
    AND (PCA.PostCreationDate BETWEEN UAS.FirstPostDate AND UAS.LatestPostDate - INTERVAL '1 month' OR PCA.PostAgeDays < 90)

UNION ALL

-- Second branch of the UNION ALL: focuses on identifying new and rapidly emerging contributors.
SELECT
    UAS_New.UserId,
    UAS_New.DisplayName,
    UAS_New.Reputation,
    UAS_New.UserCreationDate,
    UAS_New.TotalQuestionsPosted,
    UAS_New.TotalAnswersPosted,
    UAS_New.TotalPostsCreated,
    UAS_New.TotalCommentsMade,
    UAS_New.AvgPostScore,
    BM_New.GoldBadges,
    BM_New.SilverBadges,
    BM_New.BronzeBadges,
    BM_New.BadgeRank,
    PCA_New.PostId,
    PCA_New.PostTypeName,
    PCA_New.Title,
    PCA_New.Score AS PostScore,
    PCA_New.ViewCount AS PostViewCount,
    PCA_New.PostAgeDays,
    PCA_New.PostStatus,
    PCA_New.NumberOfTags,
    PCA_New.SignificantHistoryEventCount,
    PCA_New.AvgCommentScore,
    PCA_New.ContentDensityScore,
    T_New.TagName AS PrimaryTrendingTag,
    T_New.TotalTagViewCount AS PrimaryTrendingTagViews,
    T_New.AvgTagPostScore AS PrimaryTrendingTagAvgScore,
    AVG(UAS_New.Reputation) OVER (PARTITION BY BM_New.BadgeRank) AS AvgReputationInBadgeRank,
    COUNT(PCA_New.PostId) OVER (PARTITION BY UAS_New.UserId ORDER BY PCA_New.PostCreationDate) AS CumulativePostsByDate,
    CAST(UAS_New.TotalQuestionsPosted AS NUMERIC) / NULLIF(UAS_New.TotalPostsCreated, 0) AS PercentQuestions,
    'Emerging Contributor' AS UserInfluenceCategory,
    CONCAT_WS(' | ',
        PCA_New.PostStatus,
        SUBSTRING(COALESCE(PCA_New.Title, 'No Title'), 1, 40),
        ARRAY_TO_STRING((SELECT ARRAY_AGG(tag_val) FROM (SELECT tag_val FROM UNNEST(string_to_array(SUBSTRING(PCA_New.Tags, 2, LENGTH(PCA_New.Tags) - 2), '><')) AS tag_val ORDER BY 1 LIMIT 3) AS limited_tags), ', ')
    ) AS PostSummaryInfo,
    COALESCE(PCA_New.FavoriteCount, 0) + (COALESCE(PCA_New.CommentCount, 0) * 0.75) + (COALESCE(PCA_New.AnswerCount, 0) * 2.5) AS EngagementScore,
    (SELECT COUNT(DISTINCT PCM.RelatedPostId) FROM PostCollaborationMetrics AS PCM WHERE PCM.SourceOwnerUserId = UAS_New.UserId OR PCM.RelatedOwnerUserId = UAS_New.UserId) AS CollaboratedPostsCount
FROM
    UserActivitySummary AS UAS_New
LEFT JOIN
    BadgeMetrics AS BM_New ON UAS_New.UserId = BM_New.UserId
LEFT JOIN
    PostContentAnalysis AS PCA_New ON UAS_New.UserId = PCA_New.OwnerUserId
LEFT JOIN LATERAL (
    SELECT TT.TagName, TT.TotalTagViewCount, TT.AvgTagPostScore
    FROM TrendingTags AS TT
    WHERE PCA_New.Tags LIKE CONCAT('%<', TT.TagName, '>%')
    ORDER BY TT.TotalTagViewCount DESC, TT.AvgTagPostScore DESC
    LIMIT 1
) AS T_New ON TRUE
WHERE
    UAS_New.CreationDate >= NOW() - INTERVAL '1 year' -- Users created in the last year
    AND UAS_New.TotalPostsCreated > 15 -- Have created a reasonable number of posts
    AND UAS_New.Reputation > 250 -- Gained some initial reputation
    AND UAS_New.RepPerDayActive > 1.0 -- Actively gaining reputation
    AND PCA_New.PostId IS NOT NULL
ORDER BY
    Reputation DESC, GoldBadges DESC, EngagementScore DESC
LIMIT 1000;
