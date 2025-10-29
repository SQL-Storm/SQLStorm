-- {"query": "1115.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2661} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
        SUM(p.Score) AS TotalPostScore,
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore,
        MAX(COALESCE(p.LastActivityDate, p.CreationDate, c.CreationDate)) AS LastActivityEver,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViewCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views
    HAVING SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) >= 1
       AND SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) >= 1
),
PostVoteSummary AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score AS PostBaseScore,
        p.ViewCount,
        p.CommentCount,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE NULL END) AS UpvotesReceived, -- UpMod
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE NULL END) AS DownvotesReceived, -- DownMod
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE NULL END) AS FavoritesReceived, -- Favorite
        MAX(p.LastEditDate) AS LastPostEdit,
        MAX(p.LastActivityDate) AS LastPostActivity
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.ViewCount, p.CommentCount, p.LastEditDate, p.LastActivityDate
),
UserBadgeAchievements AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeAwardDate
    FROM Badges b
    GROUP BY b.UserId
),
HighReputationUsersWithActivity AS (
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.QuestionsPosted,
        ue.AnswersPosted,
        ue.TotalPostScore,
        ue.TotalComments,
        ue.TotalCommentScore,
        ue.LastActivityEver,
        ue.UserCreationDate,
        ue.Location,
        ue.Views,
        uba.GoldBadges,
        uba.SilverBadges,
        uba.BronzeBadges,
        uba.LastBadgeAwardDate,
        -- Calculate an engagement ratio incorporating various factors, normalized by user's age
        (CAST(ue.TotalPostScore AS NUMERIC) + COALESCE(ue.TotalCommentScore, 0) + (COALESCE(uba.TotalBadges, 0) * 10)) /
        (EXTRACT(EPOCH FROM (NOW() - ue.UserCreationDate)) / (3600 * 24 * 365.25) + 0.001) AS EngagementPerYear
    FROM UserEngagement ue
    LEFT JOIN UserBadgeAchievements uba ON ue.UserId = uba.UserId
    WHERE ue.Reputation >= 5000
      AND ue.TotalPosts > 10
      AND ue.LastActivityEver >= NOW() - INTERVAL '1 year'
),
PostQualityMetrics AS (
    SELECT
        ps.PostId,
        ps.OwnerUserId,
        ps.PostTypeId,
        ps.PostBaseScore,
        ps.UpvotesReceived,
        ps.DownvotesReceived,
        ps.FavoritesReceived,
        ps.ViewCount,
        ps.CommentCount,
        -- Calculate a complex post "quality score" based on votes and views
        (ps.PostBaseScore * 0.5) + (ps.UpvotesReceived * 0.8) - (ps.DownvotesReceived * 0.3) + (ps.FavoritesReceived * 1.5) + (COALESCE(ps.ViewCount,0) * 0.01) AS PostQualityScore,
        -- Window function: Rank posts by quality within each user's questions or answers
        RANK() OVER (PARTITION BY ps.OwnerUserId, ps.PostTypeId ORDER BY ((ps.PostBaseScore * 0.5) + (ps.UpvotesReceived * 0.8) - (ps.DownvotesReceived * 0.3) + (ps.FavoritesReceived * 1.5) + (COALESCE(ps.ViewCount,0) * 0.01)) DESC) AS PostQualityRankByUserPostType
    FROM PostVoteSummary ps
    WHERE ps.PostBaseScore > 0 OR ps.UpvotesReceived > 0
),
RecentTagUsage AS (
    SELECT
        p.OwnerUserId AS UserId,
        -- Extract, clean, and count tags from questions for recent usage analysis
        TRIM(LOWER(tags_unnested.tag)) AS TagName,
        COUNT(DISTINCT p.Id) AS TaggedPostsCount,
        SUM(p.Score) AS TaggedPostsScore,
        MAX(p.CreationDate) AS LastTagUsageDate
    FROM Posts p
    CROSS JOIN LATERAL UNNEST(CASE WHEN p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2 THEN STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><') ELSE ARRAY[]::varchar[] END) AS tags_unnested(tag)
    WHERE p.PostTypeId = 1 -- Only consider question tags for this
      AND p.CreationDate >= NOW() - INTERVAL '6 months'
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, TRIM(LOWER(tags_unnested.tag))
),
ExcludedUsers AS (
    SELECT DISTINCT ph.UserId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (12, 10) -- 12 = Post Deleted, 10 = Post Closed
      AND ph.CreationDate >= NOW() - INTERVAL '3 months'
)
-- Main query to select and combine the processed data
SELECT
    hru.UserId,
    hru.DisplayName,
    hru.Reputation,
    hru.QuestionsPosted,
    hru.AnswersPosted,
    hru.TotalPostScore,
    hru.TotalComments,
    hru.GoldBadges,
    hru.SilverBadges,
    hru.BronzeBadges,
    hru.LastActivityEver,
    hru.EngagementPerYear,
    -- Correlated subquery: Count specific 'Generalist' badges earned after user creation
    (SELECT COUNT(b.Id) FROM Badges b WHERE b.UserId = hru.UserId AND b.Name ILIKE '%Generalist%' AND b.Date > hru.UserCreationDate) AS GeneralistBadgesAfterCreation,
    -- String aggregation of top 3 recent tags, handling NULL if no recent tags
    COALESCE(
        (
            SELECT STRING_AGG(rtu.TagName || ' (' || rtu.TaggedPostsCount || ')', ', ' ORDER BY rtu.TaggedPostsScore DESC)
            FROM RecentTagUsage rtu
            WHERE rtu.UserId = hru.UserId
            GROUP BY rtu.UserId
            LIMIT 3
        ),
        'No recent tags'
    ) AS TopRecentTagsWithCount,
    -- Average Post Quality Score for user's questions
    AVG(CASE WHEN pqm.PostTypeId = 1 THEN pqm.PostQualityScore ELSE NULL END) AS AvgQuestionQualityScore,
    -- Average Post Quality Score for user's answers
    AVG(CASE WHEN pqm.PostTypeId = 2 THEN pqm.PostQualityScore ELSE NULL END) AS AvgAnswerQualityScore,
    -- Window function: Calculate percentage of user's reputation relative to highest in their location
    hru.Location,
    hru.Views AS UserViews,
    CAST(hru.Reputation AS NUMERIC) / NULLIF(MAX(hru.Reputation) OVER (PARTITION BY hru.Location), 0) * 100 AS PctReputationInLocation,
    -- Complex NULL logic and conditional expression to flag users with recent closed questions
    COALESCE(
        MAX(
            CASE
                WHEN EXISTS (SELECT 1 FROM Posts p_inner WHERE p_inner.OwnerUserId = hru.UserId AND p_inner.ClosedDate IS NOT NULL AND p_inner.LastActivityDate > NOW() - INTERVAL '6 months')
                THEN 'RecentlyClosedQuestionContributor'
                ELSE NULL
            END
        ),
        'NoRecentClosedQuestionContribution'
    ) AS UserPostStatusFlag
FROM HighReputationUsersWithActivity hru
LEFT JOIN PostQualityMetrics pqm ON hru.UserId = pqm.OwnerUserId
LEFT JOIN ExcludedUsers eu ON hru.UserId = eu.UserId
WHERE eu.UserId IS NULL -- Exclude users who have recent deleted or closed posts (demonstrates outer join with NULL logic for exclusion)
  AND hru.Reputation > (
        -- Correlated subquery: Compare user's reputation against the average reputation of users in their location with similar creation dates
        SELECT COALESCE(AVG(u2.Reputation), 0)
        FROM Users u2
        WHERE u2.Location = hru.Location
        AND u2.CreationDate >= hru.UserCreationDate - INTERVAL '1 year'
        AND u2.CreationDate <= hru.UserCreationDate + INTERVAL '1 year'
    )
GROUP BY
    hru.UserId,
    hru.DisplayName,
    hru.Reputation,
    hru.QuestionsPosted,
    hru.AnswersPosted,
    hru.TotalPostScore,
    hru.TotalComments,
    hru.GoldBadges,
    hru.SilverBadges,
    hru.BronzeBadges,
    hru.LastActivityEver,
    hru.EngagementPerYear,
    hru.UserCreationDate,
    hru.Location,
    hru.Views
HAVING
    COUNT(DISTINCT CASE WHEN pqm.PostTypeId = 1 THEN pqm.PostId ELSE NULL END) >= 3 -- Must have at least 3 questions with quality metrics
    AND COUNT(DISTINCT CASE WHEN pqm.PostTypeId = 2 THEN pqm.PostId ELSE NULL END) >= 3 -- Must have at least 3 answers with quality metrics
ORDER BY hru.EngagementPerYear DESC, hru.Reputation DESC
LIMIT 100;
