WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveComments,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostQualityMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        LENGTH(p.Body) AS BodyLength,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        (CASE WHEN (p.Score IS NULL OR (p.AnswerCount + p.CommentCount + 1) = 0) THEN NULL ELSE p.Score * (p.ViewCount + 1.0) / (p.AnswerCount + p.CommentCount + 1) END) AS EngagementScore,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityWiki'
            ELSE 'Open'
        END AS PostStatus,
        (SELECT COUNT(DISTINCT ph.Id) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        (SELECT AVG(LENGTH(pc.Text)) FROM Comments pc WHERE pc.PostId = p.Id AND pc.UserId IS NOT NULL) AS AvgCommentLengthByUsers
    FROM Posts p
),
TagPerformance AS (
    SELECT
        pm.OwnerUserId AS UserId,
        t.TagName,
        COUNT(DISTINCT pm.PostId) AS PostsPerTag,
        SUM(pm.Score) AS TagScore,
        AVG(pm.EngagementScore) AS AvgTagEngagementScore,
        ROW_NUMBER() OVER (PARTITION BY pm.OwnerUserId ORDER BY COUNT(DISTINCT pm.PostId) DESC, SUM(pm.Score) DESC) AS TagRankForUser
    FROM PostQualityMetrics pm
    JOIN Posts p ON pm.PostId = p.Id
    JOIN (
        SELECT p_inner.Id AS post_id, TRIM(BOTH '<>' FROM p_inner.Tags) AS tags, p_inner.Tags AS raw_tags
        FROM Posts p_inner
    ) tags_table ON tags_table.post_id = p.Id
    CROSS JOIN LATERAL (
        SELECT regexp_replace(tag, '-', ' ', 'g') AS TagName
        FROM (
            SELECT unnest(string_to_array(tags_table.tags, '><')) AS tag
        ) sub
    ) t
    WHERE p.Tags IS NOT NULL AND p.Tags != ''
    GROUP BY pm.OwnerUserId, t.TagName
),
RecentPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        ph.CreationDate AS EditDate,
        LAG(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEditDate,
        ph.PostHistoryTypeId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
),
ImportantPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        'HighScoreAnswer' AS ImportanceType
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score >= 50
      AND p.AnswerCount >= 5
      AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 year')
    UNION ALL
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        'HighViewLongBody' AS ImportanceType
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.ViewCount >= 10000
      AND LENGTH(p.Body) >= 1000
      AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 year')
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPosts,
    ue.QuestionCount,
    ue.AnswerCount,
    ue.TotalPostScore,
    ue.TotalPostViews,
    ue.TotalCommentsMade,
    ue.PositiveComments,
    (ue.Reputation * 1.0 / NULLIF(EXTRACT(EPOCH FROM (ue.LastAccessDate - ue.UserCreationDate)) / (3600 * 24 * 365.25), 0)) AS ReputationPerYear,
    AVG(pq.EngagementScore) AS AvgPostEngagementScore,
    SUM(pq.FavoriteCount) AS TotalFavoriteCount,
    MAX(pq.BodyLength) AS MaxPostBodyLength,
    MAX(CASE WHEN pq.PostStatus = 'Closed' THEN 1 ELSE 0 END) AS HasClosedPosts,
    COUNT(DISTINCT CASE WHEN rp.PostHistoryTypeId IN (4,5,6) THEN rp.PostId END) AS PostsWithEdits,
    AVG(CASE WHEN rp.PostHistoryTypeId IN (4,5,6) AND rp.EditDate IS NOT NULL AND rp.PreviousEditDate IS NOT NULL AND rp.EditDate <> rp.PreviousEditDate THEN EXTRACT(EPOCH FROM (rp.EditDate - rp.PreviousEditDate)) / (3600 * 24) END) AS AvgDaysBetweenEdits,
    STRING_AGG(DISTINCT tp.TagName, ', ') FILTER (WHERE tp.TagRankForUser <= 3) AS Top3TagsByPosts,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
    (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId IN (SELECT p_inner.Id FROM Posts p_inner WHERE p_inner.OwnerUserId = ue.UserId) AND pl.LinkTypeId = 3) AS TotalDuplicateLinkedPosts,
    CASE
        WHEN ue.Reputation > 10000 AND ue.TotalPosts > 50 AND ue.QuestionCount > 10 AND ue.AnswerCount > 20 THEN 'Power User'
        WHEN ue.Reputation BETWEEN 1000 AND 10000 AND ue.TotalPosts > 20 THEN 'Active Contributor'
        WHEN ue.Reputation < 1000 AND ue.TotalPosts > 5 THEN 'Aspiring User'
        ELSE 'Casual User'
    END AS UserCategory,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    AVG(NULLIF(pq.AvgCommentLengthByUsers, 0)) AS AvgUserCommentLengthOnPosts,
    MIN(pq.PostCreationDate) AS FirstPostDate,
    MAX(pq.PostCreationDate) AS LastPostDate,
    COUNT(DISTINCT ip.PostId) AS CountImportantPosts
FROM UserEngagement ue
JOIN Users u ON ue.UserId = u.Id
LEFT JOIN PostQualityMetrics pq ON ue.UserId = pq.OwnerUserId
LEFT JOIN RecentPostEdits rp ON pq.PostId = rp.PostId AND ue.UserId = rp.EditorUserId
LEFT JOIN Badges b ON ue.UserId = b.UserId
LEFT JOIN TagPerformance tp ON ue.UserId = tp.UserId AND tp.TagRankForUser <= 3
LEFT JOIN ImportantPosts ip ON ue.UserId = ip.OwnerUserId
WHERE
    ue.TotalPosts > 0
    AND ue.Reputation >= 100
    AND (u.Location LIKE '%United States%' OR u.Location LIKE '%Canada%' OR u.Location IS NULL)
    AND EXISTS (
        SELECT 1
        FROM Comments c_sub
        WHERE c_sub.UserId = ue.UserId
        AND c_sub.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
        AND lower(c_sub.Text) LIKE '%sql%'
    )
GROUP BY
    ue.UserId, ue.DisplayName, ue.Reputation, ue.TotalPosts, ue.QuestionCount, ue.AnswerCount,
    ue.TotalPostScore, ue.TotalPostViews, ue.TotalCommentsMade, ue.PositiveComments,
    ue.LastAccessDate, ue.UserCreationDate, u.Location
HAVING
    COUNT(DISTINCT pq.PostId) > 5
    AND SUM(CASE WHEN pq.PostTypeId = 1 AND pq.PostStatus = 'Answered' THEN 1 ELSE 0 END) > 2
    AND COUNT(DISTINCT ip.PostId) >= 1
ORDER BY
    ue.Reputation DESC,
    AvgPostEngagementScore DESC
LIMIT 100;