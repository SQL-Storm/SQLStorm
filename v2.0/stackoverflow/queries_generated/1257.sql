-- {"query": "1257.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2710} 
WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScoreReceived,
        AVG(COALESCE(p.Score, 0)) AS AveragePostScoreReceived,
        MAX(p.CreationDate) AS LastPostDate,
        (SELECT COUNT(DISTINCT b.Name) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgesCount,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate)) / 86400 AS DaysSinceCreation
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostModerationHistory AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS CurrentScore,
        p.ViewCount,
        p.AnswerCount,
        p.Tags, -- Keep tags for later processing
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN ph.Id END) AS EditOrRollbackCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END) AS ReopenCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN ph.Id END) AS ModerationEventCount,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN ph.CreationDate ELSE NULL END) AS LastEditDateFromHistory,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastCloseDateFromHistory,
        STRING_AGG(DISTINCT crt.Name, '; ') FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment SIMILAR TO '[0-9]+' AND crt.Name IS NOT NULL) AS CloseReasonNames
    FROM
        Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND ph.Comment = crt.Id::varchar(50)
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY
        p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.Tags
),
TagPerformance AS (
    SELECT
        tp.Tag,
        COUNT(DISTINCT pmh.PostId) AS TaggedPostsCount,
        SUM(COALESCE(pmh.CurrentScore, 0)) AS TotalTagScore,
        AVG(COALESCE(pmh.CurrentScore, 0)) AS AvgTagScore,
        AVG(COALESCE(pmh.ViewCount, 0)) AS AvgTagViewCount,
        SUM(pmh.ModerationEventCount) AS TotalTagModerationEvents,
        COUNT(DISTINCT pmh.OwnerUserId) AS DistinctUsersForTag,
        (
            SELECT p_inner.Title
            FROM Posts p_inner
            WHERE p_inner.Id = (
                SELECT p_sub.Id
                FROM Posts p_sub
                WHERE p_sub.Tags LIKE '%<' || tp.Tag || '>%'
                ORDER BY p_sub.ViewCount DESC, p_sub.Score DESC
                LIMIT 1
            )
        ) AS TopPostTitleForTag
    FROM
        PostModerationHistory pmh
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(pmh.Tags, 2, length(pmh.Tags)-2), '><')) AS tp(Tag)
    WHERE pmh.Tags IS NOT NULL AND LENGTH(pmh.Tags) > 2
    GROUP BY tp.Tag
),
UserPostTagStats AS (
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.TotalPosts,
        ue.TotalComments,
        COALESCE(SUM(pmh.EditOrRollbackCount), 0) AS UserTotalEditsOrRollbacks,
        COALESCE(SUM(pmh.CloseCount), 0) AS UserTotalCloses,
        COALESCE(SUM(pmh.ReopenCount), 0) AS UserTotalReopens,
        COALESCE(SUM(pmh.ModerationEventCount), 0) AS UserTotalModerationEvents,
        COALESCE(AVG(pmh.CurrentScore), 0) AS UserAvgPostScore,
        COALESCE(MAX(pmh.LastEditDateFromHistory), ue.LastPostDate) AS UserLastActivity,
        STRING_AGG(DISTINCT pmh.CloseReasonNames, ' | ') FILTER (WHERE pmh.CloseReasonNames IS NOT NULL) AS AllCloseReasons,
        RANK() OVER (PARTITION BY (CASE WHEN ue.Reputation >= 10000 THEN 'Legend' WHEN ue.Reputation >= 1000 THEN 'Expert' ELSE 'Apprentice' END) ORDER BY ue.Reputation DESC, ue.TotalPosts DESC) AS RankInRepTier,
        AVG(ue.AveragePostScoreReceived) OVER (ORDER BY ue.UserCreationDate ASC ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) AS AvgRepScoreNeighborhood
    FROM
        UserEngagement ue
    LEFT JOIN PostModerationHistory pmh ON ue.UserId = pmh.OwnerUserId
    GROUP BY
        ue.UserId, ue.DisplayName, ue.Reputation, ue.TotalPosts, ue.TotalComments, ue.LastPostDate, ue.UserCreationDate, ue.AveragePostScoreReceived
),
TagPerformanceForUser AS (
    SELECT
        pmh.OwnerUserId AS UserId,
        tp_inner.Tag,
        tp_inner.AvgTagScore,
        tp_inner.TopPostTitleForTag,
        ROW_NUMBER() OVER (PARTITION BY pmh.OwnerUserId ORDER BY tp_inner.AvgTagScore DESC, tp_inner.TotalTagModerationEvents DESC, tp_inner.TaggedPostsCount DESC) as rn
    FROM PostModerationHistory pmh
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(pmh.Tags, 2, length(pmh.Tags)-2), '><')) AS tp_posts(Tag)
    JOIN TagPerformance tp_inner ON tp_posts.Tag = tp_inner.Tag
    WHERE pmh.Tags IS NOT NULL AND LENGTH(pmh.Tags) > 2
)
SELECT
    upts.DisplayName,
    upts.Reputation,
    upts.TotalPosts,
    upts.UserTotalEditsOrRollbacks,
    upts.UserTotalCloses,
    upts.UserTotalReopens,
    upts.UserTotalModerationEvents,
    upts.UserAvgPostScore,
    upts.RankInRepTier,
    upts.AvgRepScoreNeighborhood,
    tp_for_user.Tag AS MostImpactfulTag,
    tp_for_user.AvgTagScore,
    tp_for_user.TopPostTitleForTag,
    'Moderation_Heavy_Contributor' AS UserTypeCategory,
    COALESCE(NULLIF(SUBSTRING(upts.DisplayName, 1, 3), 'SQL'), 'Other') AS DisplayNamePrefix,
    NULLIF(LOWER(u.Location), 'unknown') AS UserLocationLower,
    AGE(CURRENT_TIMESTAMP, u.LastAccessDate) AS TimeSinceLastAccess,
    (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = upts.UserId) AND pl.LinkTypeId = 3) AS TotalDuplicateLinksFromUserPosts
FROM
    UserPostTagStats upts
JOIN Users u ON upts.UserId = u.Id
LEFT JOIN TagPerformanceForUser tp_for_user ON upts.UserId = tp_for_user.UserId AND tp_for_user.rn = 1
WHERE
    upts.Reputation > 5000
    AND upts.UserTotalModerationEvents > 5
    AND upts.UserTotalPosts > 50
    AND u.Location IS NOT NULL AND u.Location LIKE '%England%'
    AND EXISTS (
        SELECT 1 FROM Comments c_sub WHERE c_sub.UserId = upts.UserId AND c_sub.Score > 5
    )
    AND NOT (upts.AllCloseReasons LIKE '%Off-topic%' AND upts.UserTotalCloses > upts.UserTotalReopens)
UNION ALL
SELECT
    upts.DisplayName,
    upts.Reputation,
    upts.TotalPosts,
    upts.UserTotalEditsOrRollbacks,
    upts.UserTotalCloses,
    upts.UserTotalReopens,
    upts.UserTotalModerationEvents,
    upts.UserAvgPostScore,
    upts.RankInRepTier,
    upts.AvgRepScoreNeighborhood,
    tp_for_user.Tag AS MostImpactfulTag,
    tp_for_user.AvgTagScore,
    tp_for_user.TopPostTitleForTag,
    'High_Volume_Positive_Contributor' AS UserTypeCategory,
    COALESCE(NULLIF(SUBSTRING(upts.DisplayName, 1, 3), 'SQL'), 'Other') AS DisplayNamePrefix,
    NULLIF(LOWER(u.Location), 'unknown') AS UserLocationLower,
    AGE(CURRENT_TIMESTAMP, u.LastAccessDate) AS TimeSinceLastAccess,
    (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = upts.UserId) AND pl.LinkTypeId = 3) AS TotalDuplicateLinksFromUserPosts
FROM
    UserPostTagStats upts
JOIN Users u ON upts.UserId = u.Id
LEFT JOIN TagPerformanceForUser tp_for_user ON upts.UserId = tp_for_user.UserId AND tp_for_user.rn = 1
WHERE
    upts.Reputation > 2000
    AND upts.UserTotalModerationEvents < 3
    AND upts.UserTotalPosts > 100
    AND upts.UserAvgPostScore > 5
    AND upts.UserLastActivity > CURRENT_TIMESTAMP - INTERVAL '6 months'
    AND NOT EXISTS (
        SELECT 1 FROM Badges b_sub WHERE b_sub.UserId = upts.UserId AND b_sub.Name LIKE '%Trouble%'
    )
    AND (u.Views IS NULL OR u.Views > 50)
ORDER BY
    Reputation DESC, TotalPosts DESC
LIMIT 1000;