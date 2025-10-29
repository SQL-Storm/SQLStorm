-- {"query": "1323.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3341} 
WITH RelevantPosts AS (
    -- Combines high-impact questions and well-regarded duplicate questions using UNION ALL.
    -- This CTE identifies posts of particular interest based on multiple criteria.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.Body,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount
    FROM Posts p
    WHERE
        p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') -- Ensure it's a question
        AND p.ViewCount > 5000 -- High view count
        AND p.FavoriteCount >= 50 -- Many favorites
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '3 years' -- Relatively recent posts

    UNION ALL

    -- Second part: Duplicate questions that still have a good score, indicating their utility
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.Body,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount
    FROM Posts p
    JOIN PostLinks pl ON p.Id = pl.RelatedPostId -- Join to find linked posts
    WHERE
        pl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate') -- Specifically duplicate links
        AND p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
        AND p.Score >= 100 -- High score for a duplicate
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '3 years'
),
PostEditHistory AS (
    -- Extracts detailed edit history for relevant posts, calculating time between consecutive edits.
    SELECT
        peh.PostId,
        peh.CreationDate AS EditDate,
        peh.UserId AS EditorUserId,
        -- Window function: Calculate the previous edit date for the same post
        LAG(peh.CreationDate) OVER (PARTITION BY peh.PostId ORDER BY peh.CreationDate) AS PreviousEditDate,
        -- Window function: Calculate hours between current and previous edit
        EXTRACT(EPOCH FROM (peh.CreationDate - LAG(peh.CreationDate) OVER (PARTITION BY peh.PostId ORDER BY peh.CreationDate))) / 3600 AS HoursSincePreviousEdit
    FROM PostHistory peh
    WHERE peh.PostHistoryTypeId IN (
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Edit Title'),
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Edit Body'),
        (SELECT Id FROM PostHistoryTypes WHERE Name = 'Edit Tags')
    ) -- Only consider actual content edit events
),
UserEngagement AS (
    -- Aggregates user-level metrics based on their contributions to RelevantPosts.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT rp.PostId) AS TotalRelevantPosts,
        SUM(CASE WHEN rp.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') THEN 1 ELSE 0 END) AS TotalRelevantQuestions,
        SUM(rp.Score) AS TotalRelevantPostScore,
        AVG(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - rp.CreationDate)) / 3600 / 24) AS AvgDaysSinceRelevantPostCreation,
        MAX(rp.CreationDate) AS LastRelevantPostCreationDate,
        -- A calculated "Influence Score" combining reputation, votes, and relevant post count.
        (u.Reputation * 0.5) + (u.UpVotes * 0.2) - (u.DownVotes * 0.1) + (COUNT(DISTINCT rp.PostId) * 1.0) AS UserInfluenceScore,
        -- Categorizes users based on their contribution patterns.
        CASE
            WHEN u.Reputation > 10000 AND MAX(rp.CreationDate) < CURRENT_TIMESTAMP - INTERVAL '1 year' THEN 'Dormant High Rep'
            WHEN u.Reputation < 1000 AND COUNT(DISTINCT rp.PostId) > 10 THEN 'Rising Contributor'
            ELSE 'Established Contributor'
        END AS UserContributionCategory
    FROM Users u
    JOIN RelevantPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
    HAVING COUNT(DISTINCT rp.PostId) > 0 -- Ensure the user has at least one relevant post
),
PostComplexMetrics AS (
    -- Computes various detailed metrics for each RelevantPost, leveraging PostEditHistory.
    SELECT
        rp.PostId,
        rp.OwnerUserId,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.LastEditDate,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        COUNT(DISTINCT peh.EditorUserId) AS DistinctEditors,
        COUNT(peh.EditDate) AS TotalEditCount,
        -- Checks if the post was ever closed.
        MAX(CASE WHEN ph_all.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed') THEN 1 ELSE 0 END) AS WasClosed,
        -- Correlated subquery: Detects specific keywords in the post body related to databases/performance.
        (
            SELECT
                CASE
                    WHEN rp.Body ILIKE '%index%' OR rp.Body ILIKE '%query%' OR rp.Body ILIKE '%transaction%' OR rp.Body ILIKE '%performance%'
                    THEN TRUE
                    ELSE FALSE
                END
        ) AS ContainsDatabasePerformanceKeywords,
        -- Measures the span of activity on a post from creation to last activity.
        EXTRACT(EPOCH FROM (rp.LastActivityDate - rp.CreationDate)) / 3600 / 24 AS DaysOfActivitySpan,
        -- String expression: Counts the number of distinct tags for the post.
        (
            SELECT COUNT(t_unnest.tag)
            FROM UNNEST(string_to_array(SUBSTRING(rp.Tags, 2, LENGTH(rp.Tags)-2), '><')) AS t_unnest(tag)
            WHERE t_unnest.tag IS NOT NULL AND t_unnest.tag != ''
        ) AS NumTags,
        -- Checks for specific database-related tags.
        CASE
            WHEN rp.Tags ILIKE '%<sql>%' OR rp.Tags ILIKE '%<database>%' OR rp.Tags ILIKE '%<nosql>%' OR rp.Tags ILIKE '%<performance>%'
            THEN TRUE
            ELSE FALSE
        END AS RelatedToDatabases,
        -- Aggregated window function data: Average hours between edits for this post.
        AVG(peh.HoursSincePreviousEdit) FILTER (WHERE peh.HoursSincePreviousEdit IS NOT NULL) AS AvgHoursBetweenEdits,
        -- Count of rapid edits (within 24 hours of the previous edit).
        SUM(CASE WHEN peh.HoursSincePreviousEdit IS NOT NULL AND peh.HoursSincePreviousEdit < 24 THEN 1 ELSE 0 END) AS RapidEditCount
    FROM RelevantPosts rp
    LEFT JOIN PostEditHistory peh ON rp.PostId = peh.PostId
    LEFT JOIN PostHistory ph_all ON rp.PostId = ph_all.PostId -- Used for Post Closed status, not just edits
    WHERE rp.OwnerUserId IS NOT NULL
    GROUP BY
        rp.PostId, rp.OwnerUserId, rp.PostTypeId, rp.Score, rp.ViewCount, rp.CreationDate, rp.LastEditDate, rp.Title, rp.Tags,
        rp.AnswerCount, rp.CommentCount, rp.FavoriteCount, rp.Body, rp.LastActivityDate
),
BadgeAnalysis AS (
    -- Summarizes badge information for users, focusing on Gold, Silver, and Tag-Based badges.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = (SELECT Id FROM Badges WHERE Name = 'Gold' LIMIT 1) THEN 1 ELSE 0 END) AS GoldBadges, -- Assuming gold badge class is 1
        SUM(CASE WHEN b.Class = (SELECT Id FROM Badges WHERE Name = 'Silver' LIMIT 1) THEN 1 ELSE 0 END) AS SilverBadges, -- Assuming silver badge class is 2
        SUM(CASE WHEN b.Class = (SELECT Id FROM Badges WHERE Name = 'Bronze' LIMIT 1) THEN 1 ELSE 0 END) AS BronzeBadges, -- Assuming bronze badge class is 3
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM Badges b
    GROUP BY b.UserId
)
-- Main query: Combines all CTEs to find highly influential and active contributors.
SELECT
    ue.UserId,
    COALESCE(ue.DisplayName, 'Anonymous User ' || ue.UserId) AS EffectiveDisplayName, -- NULL logic with COALESCE and string concatenation
    ue.Reputation,
    ue.UserInfluenceScore,
    ue.UserContributionCategory,
    COALESCE(ba.GoldBadges, 0) AS GoldBadgesCount,
    COALESCE(ba.SilverBadges, 0) AS SilverBadgesCount,
    COALESCE(ba.TagBasedBadges, 0) AS TagBasedBadgesCount,
    ue.TotalRelevantPosts,
    ue.TotalRelevantQuestions,
    ue.TotalRelevantPostScore,
    -- Window function: Ranks users within their contribution category based on influence.
    ROW_NUMBER() OVER (PARTITION BY ue.UserContributionCategory ORDER BY ue.UserInfluenceScore DESC, ue.Reputation DESC) AS RankInContributionCategory,
    -- Aggregated metrics from relevant posts.
    AVG(pcm.Score) AS AvgRelevantPostScore,
    AVG(pcm.ViewCount) AS AvgRelevantPostViewCount,
    SUM(CASE WHEN pcm.ContainsDatabasePerformanceKeywords THEN 1 ELSE 0 END) AS DatabasePerformanceRelatedPostsCount,
    SUM(pcm.TotalEditCount) AS TotalEditsOnRelevantPosts,
    -- Window function: Divides users into 4 groups based on their influence score (quartiles).
    NTILE(4) OVER (ORDER BY ue.UserInfluenceScore DESC) AS InfluenceScoreQuartile,
    -- Complex predicate/expression: Categorizes user status based on badges, recent activity, and post score.
    CASE
        WHEN COALESCE(ba.GoldBadges, 0) > 0 AND ue.LastRelevantPostCreationDate >= CURRENT_TIMESTAMP - INTERVAL '6 months' AND ue.TotalRelevantPostScore > 500
        THEN 'Highly Influential & Active'
        WHEN COALESCE(ba.SilverBadges, 0) > 0 AND ue.LastRelevantPostCreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
        THEN 'Active Influencer'
        ELSE 'Contributor'
    END AS UserStatus,
    -- Correlated subquery: Retrieves the text of the most upvoted comment from any of the user's relevant posts.
    (
        SELECT c.Text
        FROM Comments c
        WHERE c.UserId = ue.UserId
        AND c.PostId IN (SELECT rp.PostId FROM RelevantPosts rp WHERE rp.OwnerUserId = ue.UserId)
        ORDER BY c.Score DESC, c.CreationDate DESC
        LIMIT 1
    ) AS TopCommentTextOnRelevantPost,
    -- Aggregated count of posts with rapid edits.
    SUM(pcm.RapidEditCount) AS TotalRapidEditPosts,
    -- String aggregation: Creates a comma-separated list of distinct tags associated with the user's relevant posts.
    (
        SELECT STRING_AGG(DISTINCT t_unnest.tag, ', ' ORDER BY t_unnest.tag)
        FROM RelevantPosts rp_tags
        JOIN UNNEST(string_to_array(SUBSTRING(rp_tags.Tags, 2, LENGTH(rp_tags.Tags)-2), '><')) AS t_unnest(tag) ON TRUE
        WHERE rp_tags.OwnerUserId = ue.UserId AND t_unnest.tag IS NOT NULL AND t_unnest.tag != ''
    ) AS DistinctRelevantTags
FROM UserEngagement ue
LEFT JOIN BadgeAnalysis ba ON ue.UserId = ba.UserId -- LEFT JOIN to include users without badges
LEFT JOIN PostComplexMetrics pcm ON ue.UserId = pcm.OwnerUserId -- LEFT JOIN to include users whose relevant posts might not have complex metrics
WHERE
    ue.UserInfluenceScore > 100 -- Filter for users deemed influential
    AND (COALESCE(ba.GoldBadges, 0) > 0 OR COALESCE(ba.SilverBadges, 0) > 0 OR ue.TotalRelevantPostScore > 200) -- Must meet certain achievement criteria
    AND ue.LastRelevantPostCreationDate IS NOT NULL -- Ensure there is a last post date, filtering out anomalies
    AND ue.UserContributionCategory NOT IN ('Dormant High Rep') -- Exclude dormant high-reputation users
GROUP BY
    ue.UserId, ue.DisplayName, ue.Reputation, ue.UserInfluenceScore, ue.UserContributionCategory,
    ba.GoldBadges, ba.SilverBadges, ba.TagBasedBadges, ue.TotalRelevantPosts, ue.TotalRelevantQuestions,
    ue.TotalRelevantPostScore, ue.LastRelevantPostCreationDate
HAVING
    SUM(pcm.TotalEditCount) > 0 OR COALESCE(ba.GoldBadges, 0) > 0 OR COALESCE(ba.SilverBadges, 0) > 0 -- Must have edited relevant posts or earned gold/silver badges
ORDER BY
    ue.UserInfluenceScore DESC, AvgRelevantPostViewCount DESC
LIMIT 50;