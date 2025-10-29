-- {"query": "1264.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3196} 

WITH UserContributionSummary AS (
    -- Aggregates basic user content contributions (posts and comments) using a set operator.
    -- This CTE prepares a foundational set of user activity that is later merged.
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPostsContributed,
        0 AS TotalCommentsContributed,
        SUM(COALESCE(p.Score, 0)) AS SumContentScore,
        MAX(p.CreationDate) AS LastContentCreationDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId

    UNION ALL

    SELECT
        c.UserId AS UserId,
        0 AS TotalPostsContributed,
        COUNT(DISTINCT c.Id) AS TotalCommentsContributed,
        SUM(COALESCE(c.Score, 0)) AS SumContentScore,
        MAX(c.CreationDate) AS LastContentCreationDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
AggregatedUserContributions AS (
    -- Consolidates the unioned contributions per user.
    SELECT
        UserId,
        SUM(TotalPostsContributed) AS TotalPosts,
        SUM(TotalCommentsContributed) AS TotalComments,
        SUM(SumContentScore) AS AggregatedContentScore,
        MAX(LastContentCreationDate) AS LastContributionDate
    FROM UserContributionSummary
    GROUP BY UserId
),
UserActivityAndReputation AS (
    -- Summarizes comprehensive user activity, reputation, and derived metrics,
    -- joining with aggregated contributions.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserGivenUpVotes,
        u.DownVotes AS UserGivenDownVotes,
        COALESCE(auc.TotalPosts, 0) AS TotalPostsOwned,
        COALESCE(auc.TotalComments, 0) AS TotalCommentsMade,
        COALESCE(auc.AggregatedContentScore, 0) AS TotalContentScore,
        MAX(GREATEST(ph.CreationDate, v.CreationDate, auc.LastContributionDate, u.LastAccessDate)) AS LatestUserActivity,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedByPosts,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceivedByPosts,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBountyEarned,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN AggregatedUserContributions auc ON u.Id = auc.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2,3,8,9) -- UpMod, DownMod, BountyStart, BountyClose
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes,
             COALESCE(auc.TotalPosts, 0), COALESCE(auc.TotalComments, 0), COALESCE(auc.AggregatedContentScore, 0)
),
PostTaggingAndScoreAnalysis AS (
    -- Extracts tags from posts, calculates correlated averages, and prepares post metadata.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(p.ClosedDate, '9999-12-31 23:59:59'::timestamp) AS ClosedDateSentinel, -- Use sentinel for NULL ClosedDate
        p.Title,
        p.Body,
        p.Tags,
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))) AS TagName,
        -- Correlated subquery: Average score of other posts of the same type by the same owner around the same time.
        (SELECT AVG(sub_p.Score)
         FROM Posts sub_p
         WHERE sub_p.PostTypeId = p.PostTypeId
           AND sub_p.OwnerUserId = p.OwnerUserId
           AND sub_p.CreationDate BETWEEN p.CreationDate - INTERVAL '90 days' AND p.CreationDate + INTERVAL '90 days'
           AND sub_p.Id != p.Id
           AND sub_p.Score IS NOT NULL
        ) AS OwnerRecentSimilarPostAvgScore_Correlated
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
      AND p.Tags IS NOT NULL
      AND LENGTH(p.Tags) > 2 -- Ensure tags are present and not empty
      AND p.CreationDate >= '2021-01-01' -- Filter for more recent posts
),
PostHistoryAndLinkedItems AS (
    -- Aggregates post history events, extracts close reasons, and lists linked/duplicate posts.
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventCount,
        MAX(ph.CreationDate) AS LastHistoryDate,
        ARRAY_AGG(DISTINCT cr.Name) FILTER (WHERE cr.Name IS NOT NULL) AS CloseReasonNames, -- Aggregates all close reason names
        STRING_AGG(DISTINCT pl_linked.RelatedPostId::text, ', ') FILTER (WHERE pl_linked.LinkTypeId = 1) AS LinkedPostIds,
        STRING_AGG(DISTINCT pl_duplicate.RelatedPostId::text, ', ') FILTER (WHERE pl_duplicate.LinkTypeId = 3) AS DuplicatePostIds
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes cr ON ph.PostHistoryTypeId = 10 AND cr.Id = CAST(ph.Comment AS smallint)
    LEFT JOIN PostLinks pl_linked ON ph.PostId = pl_linked.PostId AND pl_linked.LinkTypeId = 1
    LEFT JOIN PostLinks pl_duplicate ON ph.PostId = pl_duplicate.PostId AND pl_duplicate.LinkTypeId = 3
    GROUP BY ph.PostId
),
TagPerformanceMetrics AS (
    -- Calculates aggregated performance metrics for each tag, filtering out less active tags.
    SELECT
        TagName,
        COUNT(DISTINCT PostId) AS TotalPostsInTag,
        AVG(PostScore) AS AvgScoreInTag,
        AVG(PostViewCount) AS AvgViewCountInTag,
        MAX(PostScore) AS MaxScoreInTag,
        MIN(PostScore) AS MinScoreInTag,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY PostScore) AS MedianScoreInTag,
        (SELECT AVG(sub_pde.PostScore) FROM PostTaggingAndScoreAnalysis sub_pde WHERE sub_pde.TagName = TagPerformanceMetrics.TagName AND sub_pde.PostTypeId = 1) AS AvgQuestionScoreForTag -- Non-correlated subquery for tag-specific question score
    FROM PostTaggingAndScoreAnalysis
    GROUP BY TagName
    HAVING COUNT(DISTINCT PostId) > 100 -- Only consider tags with significant activity
)
SELECT
    uar.UserId,
    uar.DisplayName,
    uar.Reputation,
    uar.UserCreationDate,
    uar.LatestUserActivity,
    pts.PostId,
    pts.PostTypeId,
    pts.Title,
    pts.PostCreationDate,
    pts.PostScore,
    pts.PostViewCount,
    pts.AnswerCount,
    pts.CommentCount,
    pts.FavoriteCount,
    pts.TagName,
    pts.OwnerRecentSimilarPostAvgScore_Correlated,
    phl.EditCount,
    phl.CloseEventCount,
    phl.CloseReasonNames,
    phl.LinkedPostIds,
    phl.DuplicatePostIds,
    tpm.AvgScoreInTag,
    tpm.AvgViewCountInTag,
    tpm.MedianScoreInTag,
    tpm.AvgQuestionScoreForTag,
    uar.GoldBadges,
    uar.SilverBadges,
    uar.BronzeBadges,
    -- Window functions
    RANK() OVER (PARTITION BY pts.PostTypeId ORDER BY pts.PostScore DESC, pts.PostViewCount DESC) AS PostRankInType,
    DENSE_RANK() OVER (ORDER BY uar.Reputation DESC, uar.TotalPostsOwned DESC) AS GlobalUserRank,
    LAG(pts.PostScore, 1, 0) OVER (PARTITION BY uar.UserId, pts.PostTypeId ORDER BY pts.PostCreationDate) AS PreviousPostScoreByUserAndType,
    NTH_VALUE(pts.Title, 2) OVER (PARTITION BY pts.TagName ORDER BY pts.PostViewCount DESC) AS SecondMostViewedPostTitleInTag,
    AVG(pts.PostScore) OVER (PARTITION BY pts.PostTypeId, pts.TagName ORDER BY pts.PostCreationDate RANGE BETWEEN INTERVAL '6 months' PRECEDING AND CURRENT ROW) AS RollingAvgPostScoreByTagType,
    -- Complicated predicates/expressions/calculations
    COALESCE(NULLIF(REPLACE(REPLACE(LOWER(SUBSTRING(pts.Title FROM 1 FOR 100)), 'sql', 'database'), 'performance', 'speed'), ''), 'TITLE_MOD_EMPTY') AS ProcessedTitleFragment,
    CASE
        WHEN pts.PostTypeId = 1 AND pts.AcceptedAnswerId IS NOT NULL THEN 'Question_AcceptedAnswer'
        WHEN pts.PostTypeId = 1 AND pts.ClosedDateSentinel != '9999-12-31 23:59:59' THEN 'Question_Closed'
        WHEN pts.PostTypeId = 1 AND pts.AnswerCount > 0 THEN 'Question_Answered'
        WHEN pts.PostTypeId = 2 AND pts.ParentId IS NOT NULL THEN 'Answer_ToQuestion'
        ELSE 'Other_Uncategorized'
    END AS DetailedPostStatus,
    ABS(uar.Reputation - COALESCE(tpm.AvgScoreInTag * 10, 0)) AS RepVsTagPerformanceDelta, -- Calculation demonstrating NULL logic and arithmetic
    EXTRACT(DOW FROM uar.LastAccessDate) AS LastAccessDayOfWeek, -- Date function
    (SELECT COUNT(l.RelatedPostId) FROM PostLinks l WHERE l.PostId = pts.PostId AND l.LinkTypeId = 1) AS OutgoingLinkCount, -- Non-correlated subquery for post links
    (SELECT MAX(sub_p.Score) FROM Posts sub_p WHERE sub_p.OwnerUserId = uar.UserId AND sub_p.PostTypeId = 1) AS MaxQuestionScoreByUser, -- Non-correlated subquery for user's best question
    -- NULL logic and string expressions in final selection
    NULLIF(LPAD(CAST(ABS(uar.TotalPostsOwned) AS text), 5, '0'), '00000') AS PaddedPostCount_OrNullIfZero,
    (pts.Body LIKE '%<pre><code>%</pre></code>%' OR pts.Body LIKE '%`%`%') AS ContainsCodeSnippet, -- Check for code snippets
    UPPER(LEFT(COALESCE(uar.Location, 'UNKNOWN'), 10)) AS UserLocationPrefix
FROM UserActivityAndReputation uar
INNER JOIN PostTaggingAndScoreAnalysis pts ON uar.UserId = pts.OwnerUserId
LEFT JOIN PostHistoryAndLinkedItems phl ON pts.PostId = phl.PostId
LEFT JOIN TagPerformanceMetrics tpm ON pts.TagName = tpm.TagName
WHERE uar.Reputation > 7500 -- Filter for highly reputable users
  AND uar.TotalPostsOwned >= 10 -- Users with at least 10 posts
  AND pts.PostCreationDate >= '2022-06-01' -- More recent posts
  AND pts.PostScore > (SELECT AVG(PostScore) FROM PostTaggingAndScoreAnalysis WHERE PostTypeId = pts.PostTypeId) -- Post score above average for its type
  AND (phl.CloseEventCount IS NULL OR phl.CloseEventCount = 0 OR 'Duplicate' = ANY(phl.CloseReasonNames)) -- Posts not closed, or closed as duplicate
  AND (pts.TagName LIKE '%sql%' OR pts.TagName LIKE '%database%') -- Focus on specific tags
  AND uar.DisplayName IS NOT NULL AND uar.DisplayName != '' AND uar.DisplayName ~* '^[A-Z][a-z]+(\s[A-Z][a-z]+)*$' -- Regex for proper case display names
ORDER BY uar.Reputation DESC, pts.PostCreationDate DESC, pts.PostScore DESC
LIMIT 7500;
