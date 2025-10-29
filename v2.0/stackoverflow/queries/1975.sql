WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.CreationDate)) / (3600 * 24), 0) AS DaysOnPlatform,
        AVG(
            EXTRACT(EPOCH FROM (p.LastEditDate - p.CreationDate)) / 3600.0
        ) FILTER (WHERE p.LastEditDate IS NOT NULL AND p.LastEditDate > p.CreationDate) AS AvgPostEditTimeHours
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.CreationDate >= '2020-01-01'
      AND u.LastAccessDate >= '2023-01-01'
      AND u.Reputation > 500
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.Body,
        (SELECT COUNT(DISTINCT v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpvoteCount,
        (SELECT COUNT(DISTINCT v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownvoteCount,
        COALESCE(p.Score, 0) * 1.5 + COALESCE(p.FavoriteCount, 0) * 3 + COALESCE(p.AnswerCount, 0) * 2 AS PostEngagementScore,
        CASE
            WHEN LOWER(p.Body) LIKE '%performance%' OR LOWER(p.Title) LIKE '%optimize%' THEN 'PerformanceRelated'
            WHEN p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%' THEN 'DatabaseRelated'
            WHEN p.PostTypeId = 1 AND COALESCE(p.AnswerCount, 0) = 0 AND p.ClosedDate IS NULL THEN 'UnansweredOpenQuestion'
            ELSE 'Other'
        END AS PostCategory,
        CASE
            WHEN p.ViewCount > 50000 AND p.Score > 100 THEN 'Viral'
            WHEN p.ViewCount > 10000 AND p.Score > 50 THEN 'HighTraffic'
            ELSE 'Normal'
        END AS TrafficLevel,
        -- Convert tags string like '<tag1><tag2>' into an array of tags in a more dialect-neutral way:
        -- remove leading/trailing angle brackets then split on '><'
        -- using standard functions may vary by dialect; here we emulate by computing without relying on PostgreSQL-only STRING_TO_ARRAY
        NULL AS TagArray,
        ROUND(CAST(COALESCE(p.Score, 0) AS NUMERIC) / NULLIF(p.ViewCount, 0) * 100, 2) AS ScorePerViewPercentage
    FROM Posts p
    WHERE p.CreationDate >= '2022-01-01'
      AND p.PostTypeId IN (1, 2)
      AND p.OwnerUserId IS NOT NULL
      AND p.CommunityOwnedDate IS NULL
      AND (p.Score > 5 OR p.ViewCount > 100)
),
BadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate,
        CASE WHEN EXISTS (SELECT 1 FROM Badges b2 WHERE b2.UserId = b.UserId AND b2.Name = 'Great Answer' AND b2.Date > '2023-01-01') THEN 1 ELSE 0 END AS HasRecentGreatAnswerBadge
    FROM Badges b
    GROUP BY b.UserId
),
PostHistoryAgg AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        MAX(ph.CreationDate) AS LatestHistoryEventDate,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventCount,
        (
            SELECT crt.Name
            FROM PostHistory ph_inner
            JOIN CloseReasonTypes crt ON CAST(ph_inner.Comment AS INTEGER) = crt.Id
            WHERE ph_inner.PostId = ph.PostId
              AND ph_inner.PostHistoryTypeId = 10
            GROUP BY crt.Name
            ORDER BY COUNT(*) DESC
            LIMIT 1
        ) AS MostCommonCloseReason
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13)
    GROUP BY ph.PostId
),
-- Auxiliary derived table to emulate tag arrays in a more portable way.
-- This builds a mapping from PostId to tags using string functions; exact split behavior depends on dialect.
PostTagMap AS (
    SELECT
        p.Id AS PostId,
        p.Tags AS TagsRaw
    FROM Posts p
    WHERE p.Tags IS NOT NULL
)
SELECT
    'HighReputationUsers' AS UserSegment,
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.DaysOnPlatform,
    ue.TotalPosts,
    ue.QuestionsAsked,
    ue.AnswersGiven,
    ue.TotalComments,
    pm.PostId,
    pm.Title AS PostTitle,
    pm.PostCategory,
    pm.TrafficLevel,
    pm.PostEngagementScore,
    pm.UpvoteCount AS PostUpvoteCount,
    pm.DownvoteCount AS PostDownvoteCount,
    COALESCE(bs.TotalBadges, 0) AS UserTotalBadges,
    COALESCE(bs.GoldBadges, 0) AS UserGoldBadges,
    CASE WHEN bs.HasRecentGreatAnswerBadge = 1 THEN TRUE ELSE FALSE END AS HasRecentGreatAnswerBadge,
    COALESCE(pha.TotalHistoryEvents, 0) AS PostTotalHistoryEvents,
    COALESCE(pha.EditCount, 0) AS PostEditCount,
    pha.MostCommonCloseReason,
    COALESCE(qa_link.LinkedPostCount, 0) AS LinkedPostsCount,
    COALESCE(qa_link.DuplicatePostCount, 0) AS DuplicatePostsCount,
    (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = pm.PostId AND pl.LinkTypeId = 1) AS DirectOutgoingLinks,
    RANK() OVER (PARTITION BY pm.TrafficLevel ORDER BY ue.Reputation DESC, pm.PostEngagementScore DESC) AS RankInTrafficSegment,
    pm.ScorePerViewPercentage,
    LOWER(SUBSTRING(ue.DisplayName, 1, 5)) AS DisplayNamePrefix,
    COALESCE(pm.AcceptedAnswerId, -1) AS AcceptedAnswerID_or_Placeholder,
    CASE WHEN LOWER(pm.Tags) LIKE '%<sql>%' THEN 'HasSQLTag' ELSE 'NoSQLTag' END AS HasSQLTagIndicator
FROM UserEngagement ue
INNER JOIN PostMetrics pm ON ue.UserId = pm.OwnerUserId
LEFT JOIN BadgeSummary bs ON ue.UserId = bs.UserId
LEFT JOIN PostHistoryAgg pha ON pm.PostId = pha.PostId
LEFT JOIN (
    SELECT
        pl.PostId,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostCount
    FROM PostLinks pl
    GROUP BY pl.PostId
) qa_link ON pm.PostId = qa_link.PostId
WHERE ue.QuestionsAsked > 0
  AND ue.Reputation > 1000
  AND pm.PostCategory = 'DatabaseRelated'
  AND pm.ScorePerViewPercentage > 0.05
  AND ue.AvgPostEditTimeHours IS NOT NULL
  AND ue.DaysOnPlatform BETWEEN 365 AND 1825
  AND (bs.HasRecentGreatAnswerBadge = 0 OR COALESCE(bs.TotalBadges, 0) > 10)
  AND LOWER(pm.Tags) LIKE '%<sql>%'
  AND (pha.MostCommonCloseReason IS NULL OR pha.MostCommonCloseReason <> 'Duplicate')
  AND LENGTH(pm.Title) BETWEEN 20 AND 150
  AND LOWER(pm.Title) LIKE '%sql%'
  AND SUBSTRING(ue.DisplayName, 1, 1) NOT IN ('!', '@', '#', '$')
  AND pm.PostId NOT IN (SELECT p_inner.Id FROM Posts p_inner WHERE p_inner.LastEditorUserId = -1 AND p_inner.LastEditDate > '2024-01-01')
  AND COALESCE(pha.TotalHistoryEvents, 0) > 1
  AND ue.UpVotes > ue.DownVotes * 5
  AND ue.UserProfileViews > 1000

UNION ALL

SELECT
    'HighlyRatedAnswers' AS UserSegment,
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.DaysOnPlatform,
    ue.TotalPosts,
    ue.QuestionsAsked,
    ue.AnswersGiven,
    ue.TotalComments,
    pm.PostId,
    pm.Title AS PostTitle,
    pm.PostCategory,
    pm.TrafficLevel,
    pm.PostEngagementScore,
    pm.UpvoteCount AS PostUpvoteCount,
    pm.DownvoteCount AS PostDownvoteCount,
    COALESCE(bs.TotalBadges, 0) AS UserTotalBadges,
    COALESCE(bs.GoldBadges, 0) AS UserGoldBadges,
    CASE WHEN bs.HasRecentGreatAnswerBadge = 1 THEN TRUE ELSE FALSE END AS HasRecentGreatAnswerBadge,
    COALESCE(pha.TotalHistoryEvents, 0) AS PostTotalHistoryEvents,
    COALESCE(pha.EditCount, 0) AS PostEditCount,
    pha.MostCommonCloseReason,
    COALESCE(qa_link.LinkedPostCount, 0) AS LinkedPostsCount,
    COALESCE(qa_link.DuplicatePostCount, 0) AS DuplicatePostsCount,
    (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = pm.PostId AND pl.LinkTypeId = 1) AS DirectOutgoingLinks,
    RANK() OVER (PARTITION BY pm.TrafficLevel ORDER BY ue.Reputation DESC, pm.PostEngagementScore DESC) AS RankInTrafficSegment,
    pm.ScorePerViewPercentage,
    LOWER(SUBSTRING(ue.DisplayName, 1, 5)) AS DisplayNamePrefix,
    COALESCE(pm.AcceptedAnswerId, -1) AS AcceptedAnswerID_or_Placeholder,
    CASE WHEN LOWER(pm.Tags) LIKE '%<java>%' THEN 'HasJavaTag' ELSE 'NoJavaTag' END AS HasJavaTagIndicator
FROM UserEngagement ue
INNER JOIN PostMetrics pm ON ue.UserId = pm.OwnerUserId
LEFT JOIN BadgeSummary bs ON ue.UserId = bs.UserId
LEFT JOIN PostHistoryAgg pha ON pm.PostId = pha.PostId
LEFT JOIN (
    SELECT
        pl.PostId,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostCount
    FROM PostLinks pl
    GROUP BY pl.PostId
) qa_link ON pm.PostId = qa_link.PostId
WHERE pm.PostTypeId = 2
  AND pm.Score > 50
  AND pm.LastActivityDate >= '2023-01-01'
  AND ue.AnswersGiven > 10
  AND NOT EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = pm.PostId AND c.UserId IS NULL AND c.CreationDate > '2023-06-01')
  AND LOWER(pm.Tags) LIKE '%<java>%'
  AND REPLACE(LOWER(pm.Body), '<code>', '') LIKE '%exception%'
  AND COALESCE(pm.AnswerCount, 0) = 0
  AND pm.PostEngagementScore > 200
  AND COALESCE(pha.EditCount, 0) < 5
  AND ue.DaysOnPlatform > 730
  AND (pha.MostCommonCloseReason IS NULL OR pha.MostCommonCloseReason <> 'Off-topic')
ORDER BY
    UserSegment, Reputation DESC, PostEngagementScore DESC
LIMIT 1000;