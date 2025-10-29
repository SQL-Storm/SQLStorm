-- {"query": "1644.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2999} 

WITH UserActivitySummary AS (
    -- CTE 1: Aggregates user-level metrics, calculates user "influence score", and categorizes users.
    SELECT
        u.Id AS UserId,
        COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS SumPostScore,
        SUM(COALESCE(c.Score, 0)) AS SumCommentScore,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        MAX(b.Date) AS LatestBadgeDate,
        (u.UpVotes - u.DownVotes) AS NetVotesGivenByOthers,
        COALESCE(CAST(SUM(p.FavoriteCount) AS DECIMAL), 0) AS TotalFavoritesReceived,
        (EXTRACT(EPOCH FROM (NOW() - u.CreationDate)) / (60 * 60 * 24 * 365.25)) AS UserAgeYears,
        -- Complex calculation for a hypothetical influence score and user segment
        (
            (u.Reputation * 0.5) +
            (COUNT(DISTINCT p.Id) * 0.2) +
            (SUM(COALESCE(p.Score, 0)) * 0.15) +
            (COUNT(DISTINCT b.Id) * 0.1) +
            (COALESCE(SUM(p.FavoriteCount), 0) * 0.05)
        ) AS InfluenceScore,
        CASE
            WHEN u.Reputation >= 20000 AND COUNT(DISTINCT p.Id) >= 100 THEN 'Legendary_Contributor'
            WHEN u.Reputation >= 5000 AND SUM(COALESCE(p.Score, 0)) >= 500 THEN 'Distinguished_Expert'
            WHEN u.Reputation >= 1000 THEN 'Active_Participant'
            ELSE 'Engaging_Novice'
        END AS UserSegment
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostVersionHistory AS (
    -- CTE 2: Captures post edit history, calculates edit frequency, and identifies initial versions.
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        ph.CreationDate AS HistoryDate,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_latest_history,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousHistoryDate,
        COUNT(ph.Id) OVER (PARTITION BY ph.PostId) AS TotalHistoryEventsForPost
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (1, 2, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15) -- Initial, Edit, Rollback, Close, Reopen, Delete, Lock events
    AND ph.CreationDate >= (NOW() - INTERVAL '3 years')
),
PostPerformanceMetrics AS (
    -- CTE 3: Calculates various performance metrics for posts, including window functions and specific tag analysis.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.ClosedDate,
        p.AcceptedAnswerId,
        p.LastActivityDate,
        -- String processing: check for specific keywords in title/body and parse tags
        CASE WHEN LOWER(p.Title) LIKE '%sql%' OR LOWER(p.Body) LIKE '%database%' THEN TRUE ELSE FALSE END AS ContainsDbKeywords,
        ARRAY_LENGTH(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'), 1) AS NumTags,
        -- Window function: Rank posts by score within each user's questions or answers, for recent posts
        RANK() OVER (
            PARTITION BY p.OwnerUserId, p.PostTypeId
            ORDER BY p.Score DESC, p.CreationDate DESC
        ) AS RankScorePerTypeByUser,
        -- Window function: Calculate average view count for posts created within 30 days of the current post by the same user
        AVG(p.ViewCount) OVER (
            PARTITION BY p.OwnerUserId
            ORDER BY p.CreationDate
            RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW
        ) AS RollingAvgViewCount30Days,
        -- Window function: Count total votes (UpMod + DownMod) for a post
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId IN (2, 3)) OVER (PARTITION BY p.Id) AS TotalVotesOnPost,
        MAX(CASE WHEN phv.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS IsClosedPost,
        MAX(CASE WHEN phv.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS WasReopenedPost
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory phv ON p.Id = phv.PostId
    WHERE p.OwnerUserId IS NOT NULL
    AND p.CreationDate >= (NOW() - INTERVAL '2 years') -- Focus on recent activity
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, pt.Name, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Title, p.Tags, p.ClosedDate, p.AcceptedAnswerId, p.LastActivityDate
),
BadgeInsights AS (
    -- CTE 4: Focus on badge types and user demographics for badge acquisition.
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Date AS BadgeDate,
        b.Class AS BadgeClass,
        b.TagBased,
        u.CreationDate AS UserCreationDate,
        u.Reputation AS UserReputationAtBadge,
        -- Correlated Subquery: Find the user's reputation at the time of the badge award
        (SELECT Reputation FROM Users WHERE Id = b.UserId) AS CurrentReputation,
        -- NULL logic: If Badge is not tag-based, categorize as 'General', otherwise use badge name
        COALESCE(b.Name, 'N/A') AS EffectiveBadgeIdentifier
    FROM Badges b
    JOIN Users u ON b.UserId = u.Id
    WHERE b.Date >= (NOW() - INTERVAL '1 year') -- Recent badges
    AND b.Class IN (1, 2) -- Gold or Silver badges only
)
-- Main Query: Combine all CTEs, use outer joins, set operators, correlated subqueries, and complex predicates.
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserSegment,
    uas.InfluenceScore,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.SumPostScore,
    uas.SumCommentScore,
    uas.UserAgeYears,
    pp.PostId AS TopRankedPostId,
    pp.Title AS TopRankedPostTitle,
    pp.Score AS TopRankedPostScore,
    pp.ViewCount AS TopRankedPostViewCount,
    pp.PostTypeName AS TopRankedPostType,
    pp.NumTags AS TopRankedPostNumTags,
    pp.RollingAvgViewCount30Days,
    pp.TotalVotesOnPost,
    pp.ContainsDbKeywords,
    ph.TotalHistoryEventsForPost AS PostEditCount,
    ph.HistoryDate AS LatestEditDate,
    ph.HistoryTypeName AS LatestEditType,
    bi.BadgeName AS RecentGoldOrSilverBadge,
    bi.BadgeDate AS RecentBadgeAwardDate,
    bi.EffectiveBadgeIdentifier,
    -- Correlated Subquery 1: Count of comments by the user on posts (not their own) in the last 6 months that mention a specific technology
    (
        SELECT COUNT(com.Id)
        FROM Comments com
        JOIN Posts p_com ON com.PostId = p_com.Id
        WHERE com.UserId = uas.UserId
        AND p_com.OwnerUserId IS NOT NULL AND p_com.OwnerUserId <> uas.UserId -- Commented on others' posts
        AND com.CreationDate >= (NOW() - INTERVAL '6 months')
        AND (LOWER(com.Text) LIKE '%javascript%' OR LOWER(com.Text) LIKE '%typescript%')
    ) AS RecentJsTsCommentsOnOthersPosts,
    -- Correlated Subquery 2: Check if any of user's posts (questions) have been closed AND then reopened
    (
        SELECT
            CASE WHEN EXISTS (
                SELECT 1
                FROM PostHistory ph_close
                JOIN PostHistory ph_reopen ON ph_close.PostId = ph_reopen.PostId
                WHERE ph_close.PostHistoryTypeId = 10 -- Post Closed
                AND ph_reopen.PostHistoryTypeId = 11 -- Post Reopened
                AND ph_close.PostId = pp.PostId -- Specific post
                AND ph_close.CreationDate < ph_reopen.CreationDate
            ) THEN TRUE ELSE FALSE END
    ) AS WasClosedAndReopened,
    -- Case statement with complex string and date operations
    CASE
        WHEN pp.ClosedDate IS NOT NULL AND pp.AcceptedAnswerId IS NULL THEN 'Closed_Unanswered'
        WHEN pp.AcceptedAnswerId IS NOT NULL AND pp.PostTypeId = 1 THEN 'Answered_Accepted'
        WHEN pp.CommentCount > 10 AND pp.AnswerCount = 0 THEN 'Highly_Discussed_Unanswered'
        ELSE 'Regular_Interaction'
    END AS PostStatusCategory,
    -- String manipulation and NULL coalescing
    CONCAT(
        COALESCE(SUBSTRING(uas.DisplayName, 1, 3), 'N/A'),
        '-',
        MD5(CAST(uas.UserId AS TEXT)),
        '-',
        COALESCE(SUBSTRING(uas.UserSegment, 1, 5), 'UNK')
    ) AS UserCompositeKey
FROM UserActivitySummary uas
LEFT JOIN PostPerformanceMetrics pp ON uas.UserId = pp.OwnerUserId AND pp.RankScorePerTypeByUser = 1 -- Get the highest-scored post of each type (Q/A) for the user
LEFT JOIN PostVersionHistory ph ON pp.PostId = ph.PostId AND ph.rn_latest_history = 1 -- Latest history event for the post
LEFT JOIN LATERAL ( -- Lateral join for recent gold/silver badges, ensuring we get the latest
    SELECT *
    FROM BadgeInsights bi_lat
    WHERE bi_lat.UserId = uas.UserId
    ORDER BY bi_lat.BadgeDate DESC
    LIMIT 1
) AS bi ON TRUE
WHERE uas.Reputation > 750
AND uas.TotalPosts > 5
AND uas.UserAgeYears >= 0.5 -- Filter for established users
-- Complicated predicate combining date logic, string matching, and numerical conditions
AND (
    (uas.LastAccessDate >= (NOW() - INTERVAL '3 months') AND uas.InfluenceScore > 5000) OR
    (uas.DisplayName ILIKE 'J%' AND uas.TotalQuestions > 0 AND uas.SumPostScore > 100) OR
    (uas.DisplayName IS NULL AND uas.UserAgeYears > 2 AND uas.TotalAnswers > 5)
)
ORDER BY uas.InfluenceScore DESC, uas.LastAccessDate DESC, uas.Reputation DESC
LIMIT 5000;
