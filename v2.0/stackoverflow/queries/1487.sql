-- {"query": "1487.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3469} 
WITH UserPostAggregates AS (
    -- CTE 1: Aggregates post-related statistics for each user, including complex calculations and string operations.
    -- Processes 'Tags' column for distinct tag counts and specific tag presence.
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(AVG(p.Score), 0.0) AS AvgPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate,
        -- Calculate the number of distinct tags used by the user, handling NULLs and empty tag strings.
        COUNT(DISTINCT LTRIM(RTRIM(tag))) FILTER (WHERE tag IS NOT NULL AND LTRIM(RTRIM(tag)) <> '') AS DistinctTagsUsed,
        -- Correlated subquery example: Checks if the user has any question with 'sql' or 'database' tag.
        MAX(CASE WHEN EXISTS (
            SELECT 1 FROM Posts sq_p
            WHERE sq_p.OwnerUserId = p.OwnerUserId
              AND sq_p.PostTypeId = 1
              AND sq_p.Tags IS NOT NULL
              AND (LOWER(sq_p.Tags) LIKE '%<sql>%' OR LOWER(sq_p.Tags) LIKE '%<database>%')
        ) THEN 1 ELSE 0 END) AS HasSqlOrDatabaseQuestion
    FROM
        Posts p
    CROSS JOIN LATERAL UNNEST(
        -- String expression: Parses the 'Tags' string into an array, removing leading/trailing '<' and '>'.
        -- Handles cases where Tags might be NULL or empty by returning an empty array.
        CASE WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
             THEN STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')
             ELSE ARRAY[]::text[]
        END
    ) AS tag
    WHERE
        p.OwnerUserId IS NOT NULL
        AND p.CreationDate >= '2020-01-01' -- Filter for recent post activity.
    GROUP BY
        p.OwnerUserId
),
UserInteractionSummary AS (
    -- CTE 2: Summarizes user's comments and votes they've received on their posts.
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        -- Correlated subqueries for votes received on user's posts.
        (SELECT COUNT(v.Id) FROM Votes v JOIN Posts p_v ON v.PostId = p_v.Id WHERE p_v.OwnerUserId = u.Id AND v.VoteTypeId = 2) AS ReceivedUpVotesOnPosts,
        (SELECT COUNT(v.Id) FROM Votes v JOIN Posts p_v ON v.PostId = p_v.Id WHERE p_v.OwnerUserId = u.Id AND v.VoteTypeId = 3) AS ReceivedDownVotesOnPosts
    FROM
        Users u
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    GROUP BY
        u.Id
),
UserBadgeSummary AS (
    -- CTE 3: Summarizes badge counts for each user and ranks them by Gold badges.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate,
        -- Window function: Ranks users by total Gold badges, then by total badges.
        DENSE_RANK() OVER (ORDER BY SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) DESC, COUNT(b.Id) DESC) AS GoldBadgeRank
    FROM
        Badges b
    GROUP BY
        b.UserId
),
PostHistoryTimeline AS (
    -- CTE 4: Extracts and categorizes specific post history events, including string analysis on comments.
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS HistoryDate,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        COALESCE(ph.Comment, 'No Comment Provided') AS HistoryComment,
        -- Complicated string expression: Normalizes and categorizes comments based on keywords.
        CASE
            WHEN LOWER(REPLACE(REPLACE(ph.Comment, 'edit', 'modified'), 'rollback', 'reverted')) LIKE '%duplicate%' THEN 'Duplicate Related'
            WHEN LOWER(ph.Comment) LIKE '%closed%' THEN 'Closure Related'
            WHEN LOWER(ph.Comment) LIKE '%reopened%' THEN 'Reopen Related'
            ELSE 'Other History'
        END AS CommentCategory,
        -- Window function: Finds the previous history event date for the same post, handling the first event.
        LAG(ph.CreationDate, 1, '1970-01-01'::timestamp) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PrevHistoryDate
    FROM
        PostHistory ph
    JOIN
        PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE
        -- Filter for significant history events (edits, closes, reopens, deletes).
        ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13)
        AND ph.CreationDate > '2021-01-01' -- Focus on recent history.
),
UserRecentUnifiedActivity AS (
    -- CTE 5: Uses set operators to combine different types of recent user activities into a single stream.
    SELECT UserId, LastPostDate AS ActivityDate, 'Post' AS ActivityType FROM UserPostAggregates
    UNION ALL
    SELECT UserId, LastCommentDate AS ActivityDate, 'Comment' AS ActivityType FROM UserInteractionSummary WHERE LastCommentDate IS NOT NULL
    UNION ALL
    SELECT UserId, LastBadgeDate AS ActivityDate, 'Badge' AS ActivityType FROM UserBadgeSummary WHERE LastBadgeDate IS NOT NULL
),
GlobalMetrics AS (
    -- CTE 6: Calculates global averages for various metrics for comparison.
    SELECT
        AVG(u.Reputation) AS GlobalAvgReputation,
        AVG(p.Score) AS GlobalAvgPostScore,
        COUNT(p.Id) AS TotalPostsInDB,
        COUNT(u.Id) AS TotalUsersInDB
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
)
SELECT
    u.Id AS UserId,
    -- NULL logic: Provides a default display name for deleted users.
    COALESCE(u.DisplayName, 'Deleted User ' || u.Id) AS UserDisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views AS UserViews,
    COALESCE(u.UpVotes, 0) AS UserTotalUpVotesByOthers,
    COALESCE(u.DownVotes, 0) AS UserTotalDownVotesByOthers,
    -- Complex calculation: A weighted 'Engagement Score' combining multiple user attributes.
    (u.Reputation * 0.1 + COALESCE(upa.AvgPostScore, 0.0) * 0.5 + COALESCE(uis.TotalCommentScore, 0) * 0.2 + COALESCE(ubs.TotalBadges, 0) * 0.05 + COALESCE(u.Views, 0) * 0.001) AS EngagementScore,
    -- Window function: Calculates the percentile rank of user reputation.
    NTILE(100) OVER (ORDER BY u.Reputation) AS ReputationPercentile,
    -- Post-related statistics from UserPostAggregates CTE.
    COALESCE(upa.TotalPosts, 0) AS UserTotalPosts,
    COALESCE(upa.TotalQuestions, 0) AS UserTotalQuestions,
    COALESCE(upa.TotalAnswers, 0) AS UserTotalAnswers,
    COALESCE(upa.AvgPostScore, 0.0) AS UserAvgPostScore,
    COALESCE(upa.TotalViews, 0) AS UserTotalPostViews,
    COALESCE(upa.DistinctTagsUsed, 0) AS UserDistinctTagsUsed,
    CASE WHEN upa.HasSqlOrDatabaseQuestion = 1 THEN TRUE ELSE FALSE END AS UserHasSqlOrDatabaseQuestion,
    -- Comment and Vote-related statistics from UserInteractionSummary CTE.
    COALESCE(uis.TotalComments, 0) AS UserTotalComments,
    COALESCE(uis.TotalCommentScore, 0) AS UserTotalCommentScore,
    COALESCE(uis.ReceivedUpVotesOnPosts, 0) AS UserReceivedUpVotesOnPosts,
    COALESCE(uis.ReceivedDownVotesOnPosts, 0) AS UserReceivedDownVotesOnPosts,
    -- Badge-related statistics from UserBadgeSummary CTE.
    COALESCE(ubs.TotalBadges, 0) AS UserTotalBadges,
    COALESCE(ubs.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS UserBronzeBadges,
    ubs.GoldBadgeRank,
    -- Scalar subquery: Finds the most recent activity date across posts, comments, and badges.
    (SELECT MAX(ura.ActivityDate) FROM UserRecentUnifiedActivity ura WHERE ura.UserId = u.Id) AS LastActivityDateFromCombined,
    -- Lateral join to aggregate the most recent post history details per user.
    ph_agg.LastEditCommentCategory,
    ph_agg.TimeSinceLastEditDays,
    ph_agg.RecentEditedPostId,
    -- Comparison to global metrics from GlobalMetrics CTE.
    gm.GlobalAvgReputation,
    gm.GlobalAvgPostScore,
    -- Complicated predicate/calculation: Average daily reputation gain, handling division by zero.
    -- Uses NULLIF to avoid division by zero if user creation date is too recent or current date is the same.
    NULLIF(u.Reputation, 0) / NULLIF(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - u.CreationDate)) / (60 * 60 * 24), 0) AS AvgDailyReputationGain,
    -- Window function: Ranks users by their average daily reputation gain.
    RANK() OVER (ORDER BY NULLIF(u.Reputation, 0) / NULLIF(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - u.CreationDate)) / (60 * 60 * 24), 0) DESC) AS AvgDailyReputationGainRank,
    -- Conditional expressions with string manipulation and NULL logic for user categorization.
    CASE
        WHEN u.Location IS NOT NULL AND LOWER(u.Location) LIKE '%remote%' THEN 'Remote Worker'
        WHEN u.Location IS NOT NULL AND LENGTH(u.Location) > 50 THEN 'Long Location String'
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%github.com/%' THEN 'GitHub User'
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%.dev/%' THEN 'Developer Website'
        WHEN u.AboutMe IS NOT NULL AND LOWER(u.AboutMe) LIKE '%ai%' THEN 'AI Interest'
        ELSE 'Regular User'
    END AS UserCategory,
    -- Correlated subquery (EXISTS): Checks if the user has ever closed a post.
    CASE
        WHEN EXISTS (
            SELECT 1 FROM PostHistory ph_closed
            WHERE ph_closed.UserId = u.Id AND ph_closed.PostHistoryTypeId = 10 -- Post Closed
        ) THEN TRUE
        ELSE FALSE
    END AS HasEverClosedPost,
    -- Scalar subquery: Retrieves the title of the user's most viewed question.
    (SELECT Title FROM Posts sq_p WHERE sq_p.OwnerUserId = u.Id AND sq_p.PostTypeId = 1 ORDER BY ViewCount DESC, CreationDate DESC LIMIT 1) AS MostViewedQuestionTitle
FROM
    Users u
LEFT JOIN
    UserPostAggregates upa ON u.Id = upa.UserId
LEFT JOIN
    UserInteractionSummary uis ON u.Id = uis.UserId
LEFT JOIN
    UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN LATERAL ( -- LEFT JOIN LATERAL for per-user aggregation of PostHistoryTimeline
    -- Selects the most recent relevant history event for each user from PostHistoryTimeline.
    SELECT
        ph.UserId,
        MAX(ph.HistoryDate) AS LastEditDate,
        -- Retrieves the CommentCategory for the specific most recent edit.
        (SELECT pht_inner.CommentCategory
         FROM PostHistoryTimeline pht_inner
         WHERE pht_inner.UserId = ph.UserId AND pht_inner.HistoryDate = MAX(ph.HistoryDate)
         ORDER BY pht_inner.PostId DESC, pht_inner.HistoryDate DESC LIMIT 1) AS LastEditCommentCategory,
        EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - MAX(ph.HistoryDate))) / (60 * 60 * 24) AS TimeSinceLastEditDays,
        -- Retrieves the PostId associated with the most recent edit.
        (SELECT pht_inner.PostId
         FROM PostHistoryTimeline pht_inner
         WHERE pht_inner.UserId = ph.UserId AND pht_inner.HistoryDate = MAX(ph.HistoryDate)
         ORDER BY pht_inner.PostId DESC, pht_inner.HistoryDate DESC LIMIT 1) AS RecentEditedPostId
    FROM
        PostHistoryTimeline ph
    WHERE ph.UserId = u.Id -- Correlates with the outer query's user.
    GROUP BY ph.UserId
) AS ph_agg ON TRUE -- Connects the lateral join with the main query.
CROSS JOIN
    GlobalMetrics gm -- Cross join GlobalMetrics to make global averages available to every row.
WHERE
    u.Reputation > 1000 -- Filter for users with significant reputation.
    AND u.LastAccessDate >= '2023-01-01' -- Filter for recently active users.
    AND (upa.TotalPosts > 5 OR ubs.TotalBadges > 2) -- Ensures some level of participation.
ORDER BY
    EngagementScore DESC, u.Reputation DESC, u.LastAccessDate DESC
LIMIT 1000;