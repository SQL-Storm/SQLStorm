-- {"query": "1308.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2866} 

WITH UserActivitySummary AS (
    -- Summarizes user-specific activity, reputation metrics, and calculated age.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        DATE_PART('day', u.LastAccessDate - u.CreationDate) AS AccountAgeDays,
        COUNT(DISTINCT p.Id) AS TotalPostsContributed,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) FILTER (WHERE v.UserId = u.Id), 0) AS TotalUpVotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) FILTER (WHERE v.UserId = u.Id), 0) AS TotalDownVotesGiven,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        (u.Reputation * 1.2 + COALESCE(u.UpVotes, 0) * 0.5 - COALESCE(u.DownVotes, 0) * 0.3) AS UserInfluenceBaseScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostEngagementMetrics AS (
    -- Calculates engagement metrics for questions, aggregates tags, and counts history events.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.CommentCount AS PostCommentCount,
        COALESCE(p.FavoriteCount, 0) AS PostFavoriteCount,
        p.AcceptedAnswerId,
        (p.Score * 0.6 + p.ViewCount * 0.05 + p.CommentCount * 0.9 + COALESCE(p.FavoriteCount, 0) * 2.5) AS PostEngagementIndex,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) THEN 1 ELSE 0 END) AS TotalEditHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloseVoteHistoryCount,
        -- Aggregates distinct tag names, assuming tag format like '<tag1><tag2>'
        STRING_AGG(DISTINCT t.TagName, ',') FILTER (WHERE t.TagName IS NOT NULL AND LENGTH(t.TagName) <= 20) AS AggregatedPostTags,
        MAX(ph.CreationDate) AS LastPostHistoryActivityDate
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    -- This join is intentionally using LIKE for string pattern matching against the Tags column,
    -- which can be computationally intensive for benchmarking.
    LEFT JOIN Tags t ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE p.PostTypeId = 1 -- Focus on Question posts
      AND p.CreationDate >= '2020-01-01' -- Filter for recent activity
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.CommentCount, p.FavoriteCount, p.AcceptedAnswerId, p.Tags
),
BadgeMilestones AS (
    -- Identifies users who achieved both Gold and Silver badges and the time difference between them.
    SELECT
        b.UserId,
        MIN(CASE WHEN b.Class = 1 THEN b.Date END) AS FirstGoldBadgeDate,
        MIN(CASE WHEN b.Class = 2 THEN b.Date END) AS FirstSilverBadgeDate,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgeCount
    FROM Badges b
    WHERE b.TagBased IS FALSE -- Only consider named badges
    GROUP BY b.UserId
    HAVING
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN 1 END) >= 1
        AND COUNT(DISTINCT CASE WHEN b.Class = 2 THEN 1 END) >= 1
),
HighlyScoredCommentsByOwner AS (
    -- Identifies posts where at least one comment for that post has a score above the average comment score
    -- for that post's owner across all their comments. This is a correlated subquery example.
    SELECT DISTINCT p.Id AS PostId, p.OwnerUserId
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
      AND EXISTS (
            SELECT 1
            FROM Comments c
            WHERE c.PostId = p.Id
              AND c.Score > (
                    SELECT AVG(c2.Score)
                    FROM Comments c2
                    WHERE c2.UserId = p.OwnerUserId
                      AND c2.UserId IS NOT NULL
              )
              AND c.CreationDate > p.CreationDate -- Comment must be after post creation
        )
),
RankedUserPostData AS (
    -- Combines user and post metrics, applies window functions for ranking and aggregations.
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.UserCreationDate,
        uas.AccountAgeDays,
        uas.TotalPostsContributed,
        uas.UserInfluenceBaseScore,
        pem.PostId,
        pem.PostCreationDate,
        pem.PostScore,
        pem.PostViewCount,
        pem.PostEngagementIndex,
        pem.TotalEditHistoryCount,
        pem.TotalCloseVoteHistoryCount,
        pem.AggregatedPostTags,
        bm.FirstGoldBadgeDate,
        bm.FirstSilverBadgeDate,
        CASE
            WHEN bm.FirstGoldBadgeDate IS NOT NULL AND bm.FirstSilverBadgeDate IS NOT NULL
            THEN DATE_PART('day', bm.FirstGoldBadgeDate - bm.FirstSilverBadgeDate)
            ELSE NULL
        END AS DaysBetweenGoldSilverBadges,
        ROW_NUMBER() OVER (PARTITION BY uas.UserId ORDER BY pem.PostEngagementIndex DESC, pem.PostCreationDate DESC) AS PostRankByUser,
        AVG(pem.PostScore) OVER (PARTITION BY uas.UserId) AS AveragePostScoreForUser,
        SUM(pem.PostEngagementIndex) OVER (PARTITION BY uas.UserId) AS TotalEngagementIndexForUser,
        hscbo.PostId IS NOT NULL AS HasHighScoringRelatedComment
    FROM UserActivitySummary uas
    INNER JOIN PostEngagementMetrics pem ON uas.UserId = pem.OwnerUserId
    LEFT OUTER JOIN BadgeMilestones bm ON uas.UserId = bm.UserId
    LEFT JOIN HighlyScoredCommentsByOwner hscbo ON pem.PostId = hscbo.PostId AND pem.OwnerUserId = hscbo.OwnerUserId
    WHERE
        uas.Reputation > 7500
        AND pem.PostScore >= 20
        AND pem.PostViewCount > 10000
        AND pem.AggregatedPostTags LIKE '%sql%' OR pem.AggregatedPostTags LIKE '%performance%'
        AND (pem.AcceptedAnswerId IS NOT NULL OR pem.TotalCloseVoteHistoryCount = 0 OR pem.LastPostHistoryActivityDate < pem.PostCreationDate + INTERVAL '60 days') -- Complex NULL and date logic
        AND uas.AccountAgeDays >= 1000 -- Account must be at least 1000 days old
        AND (bm.FirstGoldBadgeDate IS NULL OR bm.FirstGoldBadgeDate >= uas.UserCreationDate + INTERVAL '1 year') -- Gold badge earned after 1 year of account.
        AND NOT EXISTS ( -- Excludes posts that were linked as duplicates early on. Correlated subquery example.
            SELECT 1
            FROM PostLinks pl
            WHERE pl.PostId = pem.PostId
              AND pl.LinkTypeId = 3 -- Duplicate link type
              AND pl.CreationDate < pem.PostCreationDate + INTERVAL '30 days' -- Linked as duplicate within 30 days
        )
),
TopInfluentialContributors AS (
    -- First branch of the UNION: Identifies highly influential contributors based on combined metrics.
    SELECT
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.AccountAgeDays,
        r.TotalPostsContributed,
        r.PostId,
        r.PostCreationDate,
        r.PostScore,
        r.PostEngagementIndex,
        r.AggregatedPostTags,
        r.FirstGoldBadgeDate,
        r.FirstSilverBadgeDate,
        ABS(r.DaysBetweenGoldSilverBadges) AS DaysBetweenBadgesAbs, -- Use ABS for a consistent metric
        r.AveragePostScoreForUser,
        r.TotalEngagementIndexForUser,
        (r.UserInfluenceBaseScore * 0.2 + r.TotalEngagementIndexForUser * 0.4 + r.AveragePostScoreForUser * 0.4) AS OverallContributionScore,
        'Top Influential Contributor' AS ContributorCategory,
        r.HasHighScoringRelatedComment,
        CASE
            WHEN r.AcceptedAnswerId IS NOT NULL THEN 'Resolved_Question'
            WHEN r.TotalCloseVoteHistoryCount > 0 THEN 'Closed_Question'
            ELSE 'Active_Question'
        END AS PostResolutionStatus
    FROM RankedUserPostData r
    WHERE
        r.PostRankByUser <= 3 -- Consider top 3 posts per user
        AND (r.DaysBetweenGoldSilverBadges IS NULL OR ABS(r.DaysBetweenGoldSilverBadges) > 30) -- Gold and Silver badges not earned too close
        AND r.HasHighScoringRelatedComment IS TRUE
        AND r.TotalEngagementIndexForUser > 1000
),
RisingStarPosts AS (
    -- Second branch of the UNION: Identifies rising high-value posts from active users.
    SELECT
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.AccountAgeDays,
        r.TotalPostsContributed,
        r.PostId,
        r.PostCreationDate,
        r.PostScore,
        r.PostEngagementIndex,
        r.AggregatedPostTags,
        r.FirstGoldBadgeDate,
        r.FirstSilverBadgeDate,
        ABS(r.DaysBetweenGoldSilverBadges) AS DaysBetweenBadgesAbs,
        r.AveragePostScoreForUser,
        r.TotalEngagementIndexForUser,
        (r.Reputation * 0.1 + r.PostEngagementIndex * 0.5 + r.AveragePostScoreForUser * 0.4) AS OverallContributionScore,
        'Rising Star Post' AS ContributorCategory,
        r.HasHighScoringRelatedComment,
        CASE
            WHEN r.AcceptedAnswerId IS NOT NULL THEN 'Resolved_Question'
            WHEN r.TotalCloseVoteHistoryCount > 0 THEN 'Closed_Question'
            ELSE 'Active_Question'
        END AS PostResolutionStatus
    FROM RankedUserPostData r
    WHERE
        r.PostRankByUser = 1 -- Only the very top post by engagement per user
        AND r.HasHighScoringRelatedComment IS FALSE -- Posts without an exceptionally scored comment
        AND r.TotalEditHistoryCount >= 5 -- Indicating significant revisions
        AND r.PostScore > r.AveragePostScoreForUser * 1.8 -- Post score significantly above user's average
        AND r.PostEngagementIndex > (SELECT AVG(PostEngagementIndex) FROM RankedUserPostData WHERE AccountAgeDays > 1500) -- Compare against average engagement for older accounts
        AND r.AggregatedPostTags LIKE '%optimization%' OR r.AggregatedPostTags LIKE '%query%' -- Specific tag interest
)
-- Final result combines the two sets of identified data
SELECT * FROM TopInfluentialContributors
UNION ALL
SELECT * FROM RisingStarPosts
ORDER BY OverallContributionScore DESC, Reputation DESC, PostCreationDate DESC;
