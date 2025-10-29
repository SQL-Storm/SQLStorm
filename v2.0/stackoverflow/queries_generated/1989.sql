-- {"query": "1989.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2926} 

WITH UserEngagement AS (
    -- Summarize user activity, reputation, and basic post/comment counts
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(P.CreationDate) AS LatestPostDate,
        MAX(C.CreationDate) AS LatestCommentDate,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostQualityHistory AS (
    -- Analyze post quality, views, edit history, and close reasons
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Score AS PostScore,
        P.ViewCount,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.ClosedDate,
        P.Tags,
        P.AcceptedAnswerId,
        (SELECT COUNT(PH_sub.Id) FROM PostHistory PH_sub WHERE PH_sub.PostId = P.Id AND PH_sub.PostHistoryTypeId IN (5, 6, 4)) AS TotalEditCount, -- Count of body/tag/title edits
        (SELECT PH_closer.UserId FROM PostHistory PH_closer WHERE PH_closer.PostId = P.Id AND PH_closer.PostHistoryTypeId = 10 ORDER BY PH_closer.CreationDate DESC LIMIT 1) AS LastCloserId, -- ID of the user who cast the last close vote
        (SELECT CR.Name FROM PostHistory PH_close_reason LEFT JOIN CloseReasonTypes CR ON CR.Id = CAST(PH_close_reason.Comment AS SMALLINT) WHERE PH_close_reason.PostId = P.Id AND PH_close_reason.PostHistoryTypeId = 10 ORDER BY PH_close_reason.CreationDate DESC LIMIT 1) AS LastCloseReason, -- Name of the last close reason
        LAG(P.LastEditDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostActivityDate, -- Date of the previous edit or initial creation for a user's post
        RANK() OVER (PARTITION BY P.OwnerUserId, P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS RankByUserPostTypeScoreViews -- Rank posts by score/views within a user's post type
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
),
TagPerformance AS (
    -- Calculate average scores and total views for popular tags
    SELECT
        Tag.TagName,
        COUNT(DISTINCT PQH.PostId) AS PostsWithTag,
        AVG(PQH.PostScore) AS AvgTagPostScore,
        SUM(PQH.ViewCount) AS TotalTagViews
    FROM PostQualityHistory PQH
    JOIN LATERAL unnest(string_to_array(substring(PQH.Tags, 2, length(PQH.Tags)-2), '><')) AS TagName_unnested ON TRUE
    JOIN Tags Tag ON LOWER(Tag.TagName) = LOWER(TagName_unnested) -- Case-insensitive tag matching
    WHERE PQH.Tags IS NOT NULL AND PQH.Tags != ''
    GROUP BY Tag.TagName
    HAVING COUNT(DISTINCT PQH.PostId) >= 50 AND SUM(PQH.ViewCount) > 10000 -- Filter for tags with significant activity
),
HighValueContributions AS (
    -- Combine high-scoring questions and answers using UNION ALL
    SELECT
        P.OwnerUserId AS UserId,
        P.Id AS PostId,
        P.PostTypeId,
        P.Score AS ContributionScore,
        P.CreationDate AS ContributionDate,
        'TopQuestion' AS ContributionType
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Score >= 100 AND P.ViewCount >= 5000
    UNION ALL
    SELECT
        P.OwnerUserId AS UserId,
        P.Id AS PostId,
        P.PostTypeId,
        P.Score AS ContributionScore,
        P.CreationDate AS ContributionDate,
        'TopAnswer' AS ContributionType
    FROM Posts P
    WHERE P.PostTypeId = 2 AND P.Score >= 75 AND P.ParentId IS NOT NULL
),
HighlyEngagedUsers AS (
    -- Identify users with high recent comment activity, excluding those who only make low-score comments
    SELECT
        C.UserId
    FROM Comments C
    WHERE C.CreationDate >= NOW() - INTERVAL '3 months' AND C.Score >= 1
    GROUP BY C.UserId
    HAVING COUNT(C.Id) >= 10
    EXCEPT -- Exclude users who only comment on posts they own (less community engagement)
    SELECT
        C_owner.UserId
    FROM Comments C_owner
    JOIN Posts P_owner ON C_owner.PostId = P_owner.Id
    WHERE C_owner.UserId = P_owner.OwnerUserId
    GROUP BY C_owner.UserId
    HAVING COUNT(C_owner.Id) = COUNT(DISTINCT C_owner.PostId) -- All comments are exclusively on their own posts
)
-- Main query combining all the insights for a comprehensive user ranking
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.TotalPosts,
    UE.QuestionCount,
    UE.AnswerCount,
    UE.TotalBadges,
    UE.TotalPostScore,
    UE.TotalCommentsMade,
    UE.LatestPostDate,
    UE.LatestCommentDate,
    TP.TagName AS TopPerformingTag,
    TP.AvgTagPostScore,
    TP.TotalTagViews,
    RecentHighQualityPosts.AvgRecentScore,
    COALESCE(HighValueContributionSummary.MaxContributionScore, 0) AS MaxHighValueContributionScore,
    HighValueContributionSummary.ContributionType AS MaxContributionType,
    (DATE_PART('day', NOW() - UE.UserCreationDate) / 365.25) AS YearsOnPlatform,
    COALESCE(PQH_MaxQ.PostScore, 0) AS MaxQuestionScore,
    COALESCE(PQH_MaxA.PostScore, 0) AS MaxAnswerScore,
    ROW_NUMBER() OVER (
        ORDER BY
            UE.Reputation DESC,
            UE.TotalPostScore DESC,
            RecentHighQualityPosts.AvgRecentScore DESC NULLS LAST,
            HighValueContributionSummary.MaxContributionScore DESC NULLS LAST,
            UE.LastAccessDate DESC
    ) AS GlobalUserRank,
    -- Correlated subquery for average score of comments made by the user in the last month
    (SELECT AVG(Score) FROM Comments C_sub WHERE C_sub.UserId = UE.UserId AND C_sub.CreationDate >= NOW() - INTERVAL '1 month') AS AvgRecentCommentScoreByOwner,
    -- Correlated subquery checking if the user has any recently closed posts
    EXISTS (SELECT 1 FROM Posts P_inner WHERE P_inner.OwnerUserId = UE.UserId AND P_inner.ClosedDate IS NOT NULL AND P_inner.ClosedDate > NOW() - INTERVAL '6 months') AS HasRecentClosedPost,
    -- Complex CASE expression combining multiple criteria to categorize user engagement
    CASE
        WHEN UE.Reputation >= 10000 AND UE.TotalBadges >= 50 AND UE.QuestionCount >= 20 AND HighValueContributionSummary.ContributionType IS NOT NULL THEN 'High Impact User (Verified)'
        WHEN UE.Reputation >= 5000 AND UE.TotalBadges >= 20 AND RecentHighQualityPosts.AvgRecentScore IS NOT NULL THEN 'Mid Tier Contributor (Active)'
        WHEN HEU.UserId IS NOT NULL AND UE.TotalPosts = 0 THEN 'Highly Engaged Commenter Only'
        WHEN HEU.UserId IS NOT NULL THEN 'Highly Engaged Commenter & Poster'
        ELSE 'General Contributor'
    END AS UserEngagementCategory,
    -- Further nested correlated subquery: retrieve the title of the user's highest scored question that is linked to another post
    (SELECT P_link.Title
     FROM Posts P_link
     JOIN PostLinks PL ON P_link.Id = PL.PostId
     WHERE P_link.OwnerUserId = UE.UserId AND P_link.PostTypeId = 1 AND PL.LinkTypeId = 1 -- LinkType 1 = Linked
     ORDER BY P_link.Score DESC
     LIMIT 1
     ) AS TopLinkedQuestionTitle
FROM UserEngagement UE
LEFT JOIN (
    -- Subquery to find the top-performing tag for each user based on average post score and total views within that tag
    SELECT DISTINCT ON (PQH_top.OwnerUserId)
        PQH_top.OwnerUserId,
        TP_top.TagName,
        TP_top.AvgTagPostScore,
        TP_top.TotalTagViews
    FROM PostQualityHistory PQH_top
    JOIN LATERAL unnest(string_to_array(substring(PQH_top.Tags, 2, length(PQH_top.Tags)-2), '><')) AS TagName_unnested ON TRUE
    JOIN TagPerformance TP_top ON LOWER(TP_top.TagName) = LOWER(TagName_unnested)
    WHERE PQH_top.Tags IS NOT NULL AND PQH_top.Tags != ''
    ORDER BY PQH_top.OwnerUserId, TP_top.AvgTagPostScore DESC, TP_top.TotalTagViews DESC
) AS TP ON UE.UserId = TP.OwnerUserId
LEFT JOIN (
    -- Subquery for average score of recent high-quality posts by a user
    SELECT
        PQH_recent.OwnerUserId,
        AVG(PQH_recent.PostScore) AS AvgRecentScore
    FROM PostQualityHistory PQH_recent
    WHERE PQH_recent.PostCreationDate >= NOW() - INTERVAL '6 months'
      AND PQH_recent.PostScore >= 5
    GROUP BY PQH_recent.OwnerUserId
    HAVING COUNT(PQH_recent.PostId) >= 3
) AS RecentHighQualityPosts ON UE.UserId = RecentHighQualityPosts.OwnerUserId
LEFT JOIN (
    -- Aggregate the highest value contribution score and its type for each user
    SELECT UserId,
           MAX(ContributionScore) AS MaxContributionScore,
           (ARRAY_AGG(ContributionType ORDER BY ContributionScore DESC))[1] AS ContributionType -- Get the type associated with the max score (PostgreSQL specific)
    FROM HighValueContributions
    GROUP BY UserId
) AS HighValueContributionSummary ON UE.UserId = HighValueContributionSummary.UserId
LEFT JOIN HighlyEngagedUsers HEU ON UE.UserId = HEU.UserId
LEFT JOIN PostQualityHistory PQH_MaxQ ON UE.UserId = PQH_MaxQ.OwnerUserId AND PQH_MaxQ.PostTypeId = 1 AND PQH_MaxQ.RankByUserPostTypeScoreViews = 1 -- User's highest scored question
LEFT JOIN PostQualityHistory PQH_MaxA ON UE.UserId = PQH_MaxA.OwnerUserId AND PQH_MaxA.PostTypeId = 2 AND PQH_MaxA.RankByUserPostTypeScoreViews = 1 -- User's highest scored answer
WHERE
    UE.Reputation >= 500 -- Filter for users with a minimum level of reputation
    AND UE.TotalPosts > 0
    AND (
        (UE.LatestPostDate IS NOT NULL AND UE.LatestPostDate >= NOW() - INTERVAL '1 year')
        OR
        (UE.LatestCommentDate IS NOT NULL AND UE.LatestCommentDate >= NOW() - INTERVAL '6 months')
        OR
        HEU.UserId IS NOT NULL -- Include highly engaged commenters even if their latest post/comment is older
    ) -- Ensure recent activity or high engagement
    AND UE.DisplayName IS NOT NULL AND LENGTH(TRIM(UE.DisplayName)) > 0
    AND UE.UserCreationDate < NOW() - INTERVAL '3 months' -- Exclude very new users to focus on established contributors
ORDER BY GlobalUserRank ASC, UE.LastAccessDate DESC
LIMIT 50;
