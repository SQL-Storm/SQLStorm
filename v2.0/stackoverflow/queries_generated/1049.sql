-- {"query": "1049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3255} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score), 0) AS AvgPostScore,
        COALESCE(AVG(c.Score), 0) AS AvgCommentScore,
        MAX(ph.CreationDate) AS LastUserActivityDate, -- Max of any post history for the user
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    LEFT JOIN PostHistory AS ph ON u.Id = ph.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostEngagementMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.ClosedDate,
        SUM(v.BountyAmount) AS TotalBounty,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvotesReceived,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvotesReceived,
        COALESCE(AVG(c.Score), 0) AS AvgCommentScoreForPost,
        CASE
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 AND p.ViewCount > 0 THEN CAST(p.ViewCount AS numeric) / p.AnswerCount
            ELSE NULL
        END AS ViewsPerAnswerRatio,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostScoreRank,
        NTILE(10) OVER (ORDER BY p.ViewCount DESC, p.CreationDate DESC) AS ViewCountDecile,
        LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostDate
    FROM Posts AS p
    INNER JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    GROUP BY
        p.Id, p.PostTypeId, pt.Name, p.OwnerUserId, p.AcceptedAnswerId, p.ParentId,
        p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount,
        p.Title, p.Tags, p.ClosedDate
),
PostTagsDecomposition AS (
    SELECT
        p.Id AS PostId,
        LOWER(TRIM(unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')))) AS TagName
    FROM Posts AS p
    WHERE p.Tags IS NOT NULL AND p.Tags LIKE '<%>%'
),
AggregatedTagMetrics AS (
    SELECT
        td.TagName,
        COUNT(DISTINCT td.PostId) AS TaggedPostsCount,
        SUM(pem.PostScore) AS TotalTagScore,
        AVG(pem.PostScore) AS AvgTagScore,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT td.PostId) DESC, AVG(pem.PostScore) DESC) AS TagPopularityRank
    FROM PostTagsDecomposition AS td
    INNER JOIN PostEngagementMetrics AS pem ON td.PostId = pem.PostId
    GROUP BY td.TagName
),
PostPrimaryTag AS (
    SELECT
        ptd.PostId,
        ptd.TagName AS PrimaryTagName,
        atm.TaggedPostsCount,
        atm.TotalTagScore,
        atm.AvgTagScore,
        atm.TagPopularityRank,
        ROW_NUMBER() OVER (PARTITION BY ptd.PostId ORDER BY atm.TagPopularityRank ASC, ptd.TagName ASC) AS rn
    FROM PostTagsDecomposition AS ptd
    INNER JOIN AggregatedTagMetrics AS atm ON ptd.TagName = atm.TagName
),
RecentCloseAndReopenHistory AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LatestCloseDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS LatestCloseReasonId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS LatestReopenDate
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (10, 11) -- Post Closed, Post Reopened
    GROUP BY ph.PostId
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEntries,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.CreationDate ELSE NULL END) AS LastEditByAnyUserDate,
        (SELECT COUNT(DISTINCT UserId) FROM PostHistory WHERE PostId = ph.PostId AND PostHistoryTypeId IN (4,5,6)) AS DistinctEditors
    FROM PostHistory AS ph
    GROUP BY ph.PostId
),
CommunityOwnedStatus AS (
    SELECT
        p.Id AS PostId,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsCommunityOwned
    FROM Posts AS p
    WHERE p.CommunityOwnedDate IS NOT NULL
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.LastAccessDate,
    uas.TotalPosts,
    uas.TotalComments,
    uas.TotalBadges,
    uas.AvgPostScore,
    uas.AvgCommentScore,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    pem.PostId,
    pem.PostTypeName,
    pem.PostCreationDate,
    pem.PostScore,
    pem.ViewCount,
    pem.AnswerCount,
    pem.CommentCount,
    pem.Title,
    pem.Tags,
    pem.PostScoreRank,
    pem.ViewCountDecile,
    pem.ViewsPerAnswerRatio,
    COALESCE(rcrh.LatestCloseDate, NULL) AS PostClosedTimestamp,
    CASE
        WHEN rcrh.LatestCloseDate IS NOT NULL AND (rcrh.LatestReopenDate IS NULL OR rcrh.LatestReopenDate < rcrh.LatestCloseDate) THEN
            CASE
                WHEN rcrh.LatestCloseReasonId = '1' THEN 'Old: Exact Duplicate'
                WHEN rcrh.LatestCloseReasonId = '2' THEN 'Old: Off-topic'
                WHEN rcrh.LatestCloseReasonId = '3' THEN 'Old: Subjective and argumentative'
                WHEN rcrh.LatestCloseReasonId = '4' THEN 'Old: Not a real question'
                WHEN rcrh.LatestCloseReasonId = '7' THEN 'Old: Too localized'
                WHEN rcrh.LatestCloseReasonId = '10' THEN 'Old: General reference'
                WHEN rcrh.LatestCloseReasonId = '20' THEN 'Old: Noise or pointless'
                WHEN rcrh.LatestCloseReasonId = '101' THEN 'Current: Duplicate'
                WHEN rcrh.LatestCloseReasonId = '102' THEN 'Current: Off-topic'
                WHEN rcrh.LatestCloseReasonId = '103' THEN 'Current: Needs details or clarity'
                WHEN rcrh.LatestCloseReasonId = '104' THEN 'Current: Needs more focus'
                WHEN rcrh.LatestCloseReasonId = '105' THEN 'Current: Opinion-based'
                WHEN rcrh.LatestCloseReasonId IS NOT NULL THEN 'Unknown Close Reason'
                ELSE 'Closed (Reason Unspecified)'
            END
        ELSE 'Not Currently Closed'
    END AS PostCloseStatusAndReason,
    COALESCE(cos.IsCommunityOwned, FALSE) AS IsCommunityOwned,
    (SELECT COUNT(DISTINCT pl_sub.RelatedPostId)
     FROM PostLinks AS pl_sub
     WHERE pl_sub.PostId = pem.PostId AND pl_sub.LinkTypeId = 1) AS LinkedPostCount,
    (SELECT COUNT(DISTINCT pl_sub.RelatedPostId)
     FROM PostLinks AS pl_sub
     WHERE pl_sub.PostId = pem.PostId AND pl_sub.LinkTypeId = 3) AS DuplicatePostCount,
    (SELECT MAX(c_sub.CreationDate)
     FROM Comments AS c_sub
     WHERE c_sub.PostId = pem.PostId
    ) AS LatestCommentDateForPost,
    ppt.PrimaryTagName AS PostMostPopularTag,
    ppt.TaggedPostsCount AS PostsWithPrimaryTag,
    ppt.TotalTagScore AS ScoreOfPrimaryTag,
    ppt.TagPopularityRank AS PrimaryTagRank,
    (SELECT 1
     FROM Badges AS b_check
     WHERE b_check.UserId = uas.UserId AND b_check.Name = 'Disciplined'
     LIMIT 1) AS HasDisciplinedBadge,
    EXTRACT(EPOCH FROM (uas.LastAccessDate - uas.UserCreationDate)) / 86400.0 AS DaysSinceUserCreation,
    EXTRACT(EPOCH FROM (pem.CreationDate - pem.PreviousPostDate)) / 3600.0 AS HoursSincePreviousPost,
    CASE
        WHEN pem.PostScore > 100 AND pem.ViewCount > 5000 AND pem.AnswerCount > 5 THEN 'High Impact & Engaging'
        WHEN pem.PostScore > 50 OR pem.ViewCount > 1000 THEN 'Medium Impact'
        WHEN pem.PostScore > 0 AND pem.ViewCount > 100 THEN 'Low Impact'
        ELSE 'Minimal Impact'
    END AS PostImpactCategory,
    ph_sum.TotalHistoryEntries,
    ph_sum.DistinctEditors,
    COALESCE(ph_sum.LastEditByAnyUserDate, pem.CreationDate) AS EffectiveLastEditDate,
    NULLIF(pem.Title, '') AS CleanedTitle,
    NULLIF(pem.Tags, '') AS CleanedTags,
    CASE
        WHEN pem.OwnerUserId IS NULL THEN 'Community'
        ELSE 'User'
    END AS PostOwnerType,
    pem.UpvotesReceived,
    pem.DownvotesReceived,
    CAST(pem.UpvotesReceived AS NUMERIC) / NULLIF(CAST(pem.UpvotesReceived + pem.DownvotesReceived AS NUMERIC), 0) AS UpvoteRatio,
    (SELECT p_accepted.Score FROM Posts p_accepted WHERE p_accepted.Id = pem.AcceptedAnswerId) AS AcceptedAnswerScore
FROM UserActivitySummary AS uas
LEFT JOIN PostEngagementMetrics AS pem ON uas.UserId = pem.OwnerUserId
LEFT JOIN RecentCloseAndReopenHistory AS rcrh ON pem.PostId = rcrh.PostId
LEFT JOIN PostPrimaryTag AS ppt ON pem.PostId = ppt.PostId AND ppt.rn = 1
LEFT JOIN PostHistorySummary AS ph_sum ON pem.PostId = ph_sum.PostId
LEFT JOIN CommunityOwnedStatus AS cos ON pem.PostId = cos.PostId
WHERE
    uas.Reputation > 500
    AND uas.TotalPosts > 0
    AND pem.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    AND pem.PostCreationDate BETWEEN '2019-01-01' AND '2023-12-31'
    AND (pem.Score > 0 OR pem.FavoriteCount > 0 OR pem.UpvotesReceived > 0)
    AND pem.PostScoreRank <= 1000
    AND pem.ViewCountDecile >= 3
    AND (rcrh.LatestCloseDate IS NULL OR rcrh.LatestReopenDate > rcrh.LatestCloseDate OR rcrh.LatestCloseReasonId IN ('101', '1')) -- Not closed, or reopened, or closed as duplicate
    AND (EXISTS (SELECT 1 FROM Comments c_exist WHERE c_exist.PostId = pem.PostId AND LENGTH(c_exist.Text) > 50) OR pem.CommentCount = 0)
    AND (uas.DisplayName IS NOT NULL OR uas.AccountId IS NOT NULL)
    AND (LOWER(pem.Title) LIKE '%sql%' OR LOWER(pem.Title) LIKE '%database%')
    AND pem.UpvoteRatio IS NOT NULL
ORDER BY
    uas.Reputation DESC,
    pem.PostScore DESC,
    DaysSinceUserCreation ASC,
    pem.CreationDate DESC,
    AcceptedAnswerScore DESC NULLS LAST
LIMIT 2000;
