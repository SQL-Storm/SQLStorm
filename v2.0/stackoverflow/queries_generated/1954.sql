-- {"query": "1954.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3304} 

WITH UserReputationGrowth AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        MIN(b.Date) AS FirstBadgeDate,
        MAX(b.Date) AS LastBadgeDate,
        EXTRACT(DAY FROM (u.LastAccessDate - u.CreationDate)) AS AccountAgeDays,
        COALESCE(u.Views, 0) AS UserViews,
        CAST(u.Reputation AS numeric) / NULLIF(EXTRACT(DAY FROM (u.LastAccessDate - u.CreationDate)) + 1, 0) AS AvgReputationPerDay,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS RankByReputation
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2020-01-01' -- Focus on more recent user activity
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views
),
PostHistoryTimeline AS (
    SELECT
        ph.Id AS HistoryId,
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.CreationDate AS HistoryDate,
        ph.Comment,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ASC) AS RnHistory,
        LAG(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ASC) AS PreviousHistoryDate,
        LEAD(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ASC) AS NextHistoryDate
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.CreationDate >= '2020-01-01' -- Filter history events
),
PostEngagementMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        COALESCE(p.Score, 0) AS PostScore,
        COALESCE(p.ViewCount, 0) AS PostViewCount,
        COALESCE(p.AnswerCount, 0) AS PostAnswerCount,
        COALESCE(p.CommentCount, 0) AS PostCommentCount,
        COALESCE(p.FavoriteCount, 0) AS PostFavoriteCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        (SELECT AVG(ap.Score)
         FROM Posts ap
         WHERE ap.ParentId = p.Id AND ap.PostTypeId = 2) AS AverageAnswerScore, -- Correlated subquery for average answer score
        EXISTS (SELECT 1 FROM Posts acc_a WHERE acc_a.Id = p.AcceptedAnswerId AND acc_a.PostTypeId = 2) AS HasAcceptedAnswer,
        (SELECT MAX(c.Score) FROM Comments c WHERE c.PostId = p.Id AND c.CreationDate > p.LastEditDate) AS MaxRecentCommentScore, -- Correlated subquery for recent comments
        ARRAY_LENGTH(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'), 1) AS TagCount,
        (SELECT MIN(ht.HistoryDate) FROM PostHistoryTimeline ht WHERE ht.PostId = p.Id AND ht.HistoryTypeName = 'Initial Title') AS InitialTitleHistoryDate,
        (SELECT MAX(ht.HistoryDate) FROM PostHistoryTimeline ht WHERE ht.PostId = p.Id AND ht.HistoryTypeName IN ('Edit Title', 'Edit Body', 'Edit Tags')) AS LastEditHistoryDate,
        (SELECT MIN(pl.CreationDate) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS FirstDuplicateLinkDate
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1 -- Only questions for this CTE
      AND p.CreationDate >= '2020-01-01'
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastEditDate, p.LastActivityDate,
             p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Title, p.Tags, p.AcceptedAnswerId
    HAVING COALESCE(p.Score, 0) > 10 OR COALESCE(p.ViewCount, 0) > 100
),
PostModerationEvents AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT CASE WHEN phtl.HistoryTypeName = 'Post Closed' THEN phtl.HistoryId ELSE NULL END) AS CloseCount,
        COUNT(DISTINCT CASE WHEN phtl.HistoryTypeName = 'Post Reopened' THEN phtl.HistoryId ELSE NULL END) AS ReopenCount,
        MAX(CASE WHEN phtl.HistoryTypeName = 'Post Closed' THEN 1 ELSE 0 END) AS WasClosedEver,
        MAX(CASE WHEN phtl.HistoryTypeName = 'Post Reopened' THEN 1 ELSE 0 END) AS WasReopenedEver,
        MAX(CASE WHEN phtl.HistoryTypeName = 'Post Closed' THEN phtl.HistoryDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN phtl.HistoryTypeName = 'Post Reopened' THEN phtl.HistoryDate ELSE NULL END) AS LastReopenedDate,
        (
            SELECT crc.Name
            FROM PostHistoryTimeline phtl_inner
            JOIN CloseReasonTypes crc ON crc.Id = CAST(phtl_inner.Comment AS smallint)
            WHERE phtl_inner.PostId = p.Id
              AND phtl_inner.HistoryTypeName = 'Post Closed'
            ORDER BY phtl_inner.HistoryDate DESC
            LIMIT 1
        ) AS LastCloseReason, -- Correlated subquery for the LAST close reason
        MIN(CASE WHEN phtl.HistoryTypeName = 'Post Closed' THEN EXTRACT(EPOCH FROM (phtl.HistoryDate - p.CreationDate)) ELSE NULL END) AS TimeToFirstCloseSeconds
    FROM Posts p
    LEFT JOIN PostHistoryTimeline phtl ON p.Id = phtl.PostId
    WHERE p.PostTypeId = 1 AND p.CreationDate >= '2020-01-01'
    GROUP BY p.Id, p.CreationDate
)
-- Main query: Analyze highly engaged questions from active users, factoring in moderation status
SELECT
    URG.UserId,
    URG.DisplayName AS UserDisplayName,
    URG.Reputation,
    URG.TotalBadges,
    PEM.PostId,
    PEM.Title AS PostTitle,
    PEM.PostScore,
    PEM.PostViewCount,
    PEM.PostAnswerCount,
    PEM.PostCommentCount,
    PEM.HasAcceptedAnswer,
    PEM.AverageAnswerScore,
    PEM.MaxRecentCommentScore,
    PEM.TagCount,
    REPLACE(REPLACE(LOWER(PEM.Title), ' ', '_'), '-', '_') AS StandardizedTitleFragment, -- String manipulation
    COALESCE(PME.WasClosedEver, 0) AS IsClosed,
    COALESCE(PME.LastCloseReason, 'N/A') AS FinalCloseReason,
    CASE
        WHEN URG.Reputation > 50000 AND PEM.PostScore > 100 AND PEM.HasAcceptedAnswer IS TRUE THEN 'Elite Author - High Impact & Accepted'
        WHEN URG.Reputation > 10000 AND PEM.PostScore > 50 THEN 'Pro Author - Significant Post'
        WHEN URG.Reputation > 1000 AND PEM.PostScore > 20 THEN 'Experienced Author - Popular Post'
        WHEN URG.Reputation < 500 AND PEM.UpvotesReceived > 10 AND PEM.LastEditHistoryDate IS NOT NULL THEN 'Rising Author - Engaged Post'
        ELSE 'General Activity'
    END AS EngagementCategory, -- Complicated CASE expression
    (SELECT COUNT(DISTINCT cmt.Id)
     FROM Comments cmt
     WHERE cmt.PostId = PEM.PostId AND cmt.UserId IS NULL) AS AnonymousCommentCount, -- Correlated subquery with NULL logic
    EXTRACT(EPOCH FROM (PEM.LastActivityDate - PEM.PostCreationDate)) / 3600.0 AS HoursSinceCreationToLastActivity, -- Date calculation
    NULLIF(URG.GoldBadges, 0) * PEM.PostScore AS WeightedUserPostScore, -- Calculation with NULLIF
    -- Demonstrate string pattern matching with regexp_matches (PostgreSQL specific)
    CASE WHEN PEM.Tags ~* '(<java>|<c#>.+?)' THEN 'Java/C# Related'
         WHEN PEM.Tags ~* '(<python>|<javascript>.+?)' THEN 'Python/JS Related'
         ELSE 'Other Tech Stack'
    END AS TechStackCategory,
    -- Complex calculation for post longevity relative to activity
    NULLIF(EXTRACT(DAY FROM (NOW() - PEM.PostCreationDate)), 0) / NULLIF(PEM.PostViewCount, 0) AS PostViewLongevityRatio
FROM UserReputationGrowth URG
INNER JOIN PostEngagementMetrics PEM ON URG.UserId = PEM.OwnerUserId
LEFT JOIN PostModerationEvents PME ON PEM.PostId = PME.PostId
WHERE
    URG.AvgReputationPerDay IS NOT NULL
    AND URG.AccountAgeDays > 60 -- Filter for established users
    AND PEM.PostTypeId = 1 -- Ensure we're looking at questions
    AND (
        -- Complicated predicate combining conditions from different CTEs
        (PEM.PostScore >= 75 AND PEM.PostViewCount >= 7500 AND PEM.PostAnswerCount >= 7)
        OR
        (PEM.HasAcceptedAnswer IS TRUE AND PEM.AverageAnswerScore >= 15 AND URG.GoldBadges >= 2)
        OR
        (PEM.LastEditHistoryDate IS NOT NULL AND (PEM.LastEditHistoryDate - PEM.PostCreationDate) < INTERVAL '15 days' AND PME.WasClosedEver = 0 AND PEM.UpvotesReceived > PEM.DownvotesReceived * 2)
    )
    AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = URG.UserId AND b.Name IN ('Epic', 'Legendary')) -- Correlated subquery for specific badge
    AND (PEM.Tags ILIKE '%<sql>%' OR PEM.Tags ILIKE '%<optimization>%') -- String expression with ILIKE
    AND URG.LastAccessDate > NOW() - INTERVAL '6 months' -- More specific user activity filter
UNION ALL -- Set operator to combine with another segment of data
-- Second part of the query: Recently reopened & highly voted posts from users with 'Reviewer' badge
SELECT
    URG.UserId,
    URG.DisplayName AS UserDisplayName,
    URG.Reputation,
    URG.TotalBadges,
    PEM.PostId,
    PEM.Title AS PostTitle,
    PEM.PostScore,
    PEM.PostViewCount,
    PEM.PostAnswerCount,
    PEM.PostCommentCount,
    PEM.HasAcceptedAnswer,
    PEM.AverageAnswerScore,
    PEM.MaxRecentCommentScore,
    PEM.TagCount,
    REPLACE(REPLACE(LOWER(PEM.Title), ' ', '_'), '-', '_') AS StandardizedTitleFragment,
    COALESCE(PME.WasClosedEver, 0) AS IsClosed,
    COALESCE(PME.LastCloseReason, 'N/A') AS FinalCloseReason,
    'Recently Reopened & Highly Voted' AS EngagementCategory,
    (SELECT COUNT(DISTINCT cmt.Id) FROM Comments cmt WHERE cmt.PostId = PEM.PostId AND cmt.UserId IS NULL) AS AnonymousCommentCount,
    EXTRACT(EPOCH FROM (PEM.LastActivityDate - PEM.PostCreationDate)) / 3600.0 AS HoursSinceCreationToLastActivity,
    NULLIF(URG.GoldBadges, 0) * PEM.PostScore AS WeightedUserPostScore,
    CASE WHEN PEM.Tags ~* '(<performance>|<benchmark>|<scaling>.+?)' THEN 'Performance Related'
         WHEN PEM.Tags ~* '(<security>|<privacy>.+?)' THEN 'Security Related'
         ELSE 'Other Focus'
    END AS TechStackCategory,
    NULLIF(EXTRACT(DAY FROM (NOW() - PEM.PostCreationDate)), 0) / NULLIF(PEM.PostViewCount, 0) AS PostViewLongevityRatio
FROM UserReputationGrowth URG
INNER JOIN PostEngagementMetrics PEM ON URG.UserId = PEM.OwnerUserId
INNER JOIN PostModerationEvents PME ON PEM.PostId = PME.PostId -- INNER JOIN here because we specifically need moderated posts
WHERE
    URG.Reputation > 5000 -- Some reputation threshold
    AND PME.WasReopenedEver = 1 -- Post was reopened
    AND PEM.UpvotesReceived > 50 -- Significantly upvoted
    AND PEM.PostCommentCount >= 5 -- And has some comments
    AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = URG.UserId AND b.Name = 'Reviewer') -- Correlated subquery for 'Reviewer' badge
    AND PEM.LastActivityDate > NOW() - INTERVAL '3 months' -- Recently active posts
ORDER BY WeightedUserPostScore DESC, PostViewLongevityRatio ASC
LIMIT 200;
