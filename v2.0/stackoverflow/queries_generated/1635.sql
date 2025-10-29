-- {"query": "1635.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2634} 

WITH RawUserActivityEvents AS (
    -- User's own posts
    SELECT
        p.OwnerUserId AS UserId,
        p.CreationDate AS EventDate,
        'PostCreated' AS EventType,
        p.Id AS EventId
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
      AND p.CreationDate IS NOT NULL

    UNION ALL

    -- User's comments
    SELECT
        c.UserId AS UserId,
        c.CreationDate AS EventDate,
        'CommentCreated' AS EventType,
        c.Id AS EventId
    FROM Comments c
    WHERE c.UserId IS NOT NULL
      AND c.CreationDate IS NOT NULL

    UNION ALL

    -- User's votes (as the voter) - Upvotes & Downvotes only
    SELECT
        v.UserId AS UserId,
        v.CreationDate AS EventDate,
        CASE
            WHEN v.VoteTypeId = 2 THEN 'UpvoteGiven'
            WHEN v.VoteTypeId = 3 THEN 'DownvoteGiven'
            ELSE 'OtherVoteGiven' -- Fallback, though filtered below
        END AS EventType,
        v.Id AS EventId
    FROM Votes v
    WHERE v.UserId IS NOT NULL
      AND v.VoteTypeId IN (2, 3) -- UpMod (upvote), DownMod (downvote)
      AND v.CreationDate IS NOT NULL
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswersPosted,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT v_given.EventId) FILTER (WHERE v_given.EventType = 'UpvoteGiven') AS TotalUpvotesGiven,
        COUNT(DISTINCT v_given.EventId) FILTER (WHERE v_given.EventType = 'DownvoteGiven') AS TotalDownvotesGiven,
        COUNT(DISTINCT v_received.Id) FILTER (WHERE v_received.VoteTypeId = 2) AS TotalUpvotesReceivedOnPosts,
        COUNT(DISTINCT v_received.Id) FILTER (WHERE v_received.VoteTypeId = 3) AS TotalDownvotesReceivedOnPosts,
        MAX(rae.EventDate) AS LastEngagementDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN RawUserActivityEvents rae ON u.Id = rae.UserId
    LEFT JOIN RawUserActivityEvents v_given ON u.Id = v_given.UserId AND v_given.EventType IN ('UpvoteGiven', 'DownvoteGiven')
    LEFT JOIN Votes v_received ON p.Id = v_received.PostId AND v_received.VoteTypeId IN (2, 3)
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostExtendedDetails AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.ClosedDate,
        LOWER(COALESCE(p.Title, '')) AS NormalizedTitle,
        COALESCE(p.Tags, '') AS TagsString,
        (SELECT COUNT(ph.Id)
         FROM PostHistory ph
         WHERE ph.PostId = p.Id
           AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)) AS PostEditHistoryCount, -- Edit/Rollback Title/Body/Tags
        (SELECT COUNT(DISTINCT ph.UserId)
         FROM PostHistory ph
         WHERE ph.PostId = p.Id
           AND ph.PostHistoryTypeId IN (4, 5, 6)) AS UniqueEditors,
        CASE
            WHEN p.ClosedDate IS NOT NULL OR EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10)
            THEN 'TRUE' ELSE 'FALSE'
        END AS IsClosedFlag,
        RANK() OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByUserPostTypeScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
PostTagExtraction AS (
    SELECT
        ped.PostId,
        TRIM(UNNEST(string_to_array(SUBSTRING(ped.TagsString FROM 2 FOR LENGTH(ped.TagsString) - 2), '><'))) AS TagName
    FROM PostExtendedDetails ped
    WHERE ped.TagsString IS NOT NULL AND LENGTH(ped.TagsString) > 2
),
TagPerformanceMetrics AS (
    SELECT
        pte.TagName,
        COUNT(DISTINCT pte.PostId) AS TotalPostsWithTag,
        AVG(ped.Score) AS AverageScoreForTag,
        MAX(ped.PostCreationDate) AS LatestPostDateWithTag,
        NTILE(4) OVER (ORDER BY COUNT(DISTINCT pte.PostId) DESC, AVG(ped.Score) DESC) AS TagPopularityQuartile
    FROM PostTagExtraction pte
    JOIN PostExtendedDetails ped ON pte.PostId = ped.PostId
    GROUP BY pte.TagName
),
UserBadgeOverview AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadgesCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount,
        MAX(b.Date) AS LastBadgeAwardDate
    FROM Badges b
    GROUP BY b.UserId
),
PotentialDuplicateAnalysis AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId AS DuplicateOfPostId,
        p_dup.Title AS DuplicateOfTitle,
        p_dup.OwnerUserId AS DuplicateOfOwnerUserId,
        p_dup.Score AS DuplicateOfScore,
        p_dup.CreationDate AS DuplicateOfCreationDate
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    JOIN Posts p_dup ON pl.RelatedPostId = p_dup.Id
    WHERE lt.Name = 'Duplicate'
)
SELECT
    uas.UserId,
    u.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.LastAccessDate,
    EXTRACT(DAY FROM (NOW() - uas.UserCreationDate)) AS DaysSinceAccountCreation,
    uas.TotalQuestionsPosted,
    uas.TotalAnswersPosted,
    uas.TotalCommentsMade,
    uas.TotalUpvotesGiven,
    uas.TotalDownvotesGiven,
    uas.TotalUpvotesReceivedOnPosts,
    uas.TotalDownvotesReceivedOnPosts,
    CASE
        WHEN ubs.GoldBadgesCount > 0 THEN 'TRUE'
        ELSE 'FALSE'
    END AS HasGoldBadge,
    ubs.TotalBadgesCount,
    ped.PostId,
    ped.PostTypeId,
    ped.NormalizedTitle AS PostTitle,
    ped.Score AS PostCurrentScore,
    ped.ViewCount AS PostViewCount,
    ped.FavoriteCount AS PostFavoriteCount,
    ped.AnswerCount AS PostAnswerCount,
    ped.IsClosedFlag,
    ped.PostEditHistoryCount,
    ped.UniqueEditors,
    ph.CreationDate AS LastPostModificationDate,
    ph.PostHistoryTypeId AS LastPostHistoryType,
    pht.Name AS LastPostHistoryTypeName,
    COALESCE(ph.Comment, 'N/A') AS LastPostHistoryComment,
    cr.Name AS CloseReasonIfClosed,
    pda.DuplicateOfPostId,
    pda.DuplicateOfTitle AS DuplicateTargetTitle,
    tpm.TagName AS AssociatedTagName,
    tpm.TotalPostsWithTag,
    tpm.AverageScoreForTag,
    tpm.TagPopularityQuartile,
    LAG(ped.Score, 1, 0) OVER (PARTITION BY uas.UserId ORDER BY ped.PostCreationDate) AS ScoreOfPreviousPost,
    LEAD(ped.Score, 1, 0) OVER (PARTITION BY uas.UserId ORDER BY ped.PostCreationDate) AS ScoreOfNextPost,
    AVG(ped.Score) OVER (PARTITION BY uas.UserId ORDER BY ped.PostCreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RollingAvgScoreLast3Posts,
    CASE
        WHEN ped.NormalizedTitle LIKE '%sql%' AND ped.NormalizedTitle NOT LIKE '%nosql%' THEN 'SQL_Related'
        WHEN ped.NormalizedTitle LIKE '%python%' THEN 'Python_Related'
        ELSE 'Other_Topic'
    END AS PostTopicCategory
FROM UserActivitySummary uas
JOIN Users u ON uas.UserId = u.Id
LEFT JOIN UserBadgeOverview ubs ON uas.UserId = ubs.UserId
LEFT JOIN PostExtendedDetails ped ON uas.UserId = ped.OwnerUserId
LEFT JOIN LATERAL (
    SELECT ph_inner.PostHistoryTypeId, ph_inner.CreationDate, ph_inner.Comment
    FROM PostHistory ph_inner
    WHERE ph_inner.PostId = ped.PostId
    ORDER BY ph_inner.CreationDate DESC
    LIMIT 1
) ph ON TRUE -- Get the most recent history entry for each post
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN CloseReasonTypes cr ON ph.PostHistoryTypeId = 10 AND ph.Comment = cr.Id::varchar(50)
LEFT JOIN PostTagExtraction pte ON ped.PostId = pte.PostId
LEFT JOIN TagPerformanceMetrics tpm ON pte.TagName = tpm.TagName
LEFT JOIN PotentialDuplicateAnalysis pda ON ped.PostId = pda.PostId
WHERE
    uas.Reputation >= 5000
    AND (ped.PostId IS NULL OR ped.Score >= 10 OR ped.ViewCount >= 1000) -- Include users without posts, or posts with decent stats
    AND (u.DisplayName LIKE 'J%e' OR u.DisplayName IS NULL) -- Example string pattern/NULL logic
    AND (uas.LastEngagementDate IS NOT NULL AND uas.LastEngagementDate > NOW() - INTERVAL '1 year') -- Active within the last year
    AND (pht.Name NOT LIKE '%Deleted%' OR pht.Name IS NULL) -- Exclude deleted posts from history analysis
    AND COALESCE(ped.NormalizedTitle, '') NOT LIKE '%[spam]%'
    AND COALESCE(ped.NormalizedTitle, '') NOT LIKE '%test%'
ORDER BY
    uas.Reputation DESC,
    uas.LastEngagementDate DESC NULLS LAST,
    ped.PostCurrentScore DESC NULLS LAST,
    tpm.TagPopularityQuartile ASC NULLS LAST
LIMIT 2500;
