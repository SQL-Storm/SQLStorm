WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNum,
        CASE WHEN p.PostTypeId = 1 THEN SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)) ELSE NULL END AS Tags,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0 AND p.PostTypeId IN (1, 2)
),
UserAggregates AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        MAX(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS HasSilverBadge,
        MAX(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS HasBronzeBadge
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
),
PostActivity AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36) THEN 1 END) AS ModerationEventCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 END) AS BodyEditCount,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN ph.CreationDate ELSE NULL END) AS LastBodyEditDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
CommentStats AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount,
        AVG(c.Score) AS AverageCommentScore
    FROM Comments c
    GROUP BY c.PostId
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostCount,
        SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinkCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
)
SELECT
    rp.PostId,
    rp.Title,
    pt.Name AS PostTypeName,
    ua.DisplayName AS OwnerDisplayName,
    ua.Reputation AS OwnerReputation,
    ua.UserCreationDate AS OwnerCreationDate,
    ua.BadgeCount AS OwnerBadgeCount,
    ua.HasGoldBadge,
    ua.HasSilverBadge,
    ua.HasBronzeBadge,
    rp.PostCreationDate,
    rp.PostScore,
    rp.AnswerCount,
    rp.CommentCount AS PostCommentCount,
    COALESCE(cs.CommentCount, 0) AS TotalCommentsOnPost,
    COALESCE(cs.PositiveCommentCount, 0) AS PositiveCommentsOnPost,
    cs.AverageCommentScore,
    pa.ModerationEventCount,
    pa.BodyEditCount AS PostBodyEditCount,
    pa.LastBodyEditDate,
    poa.LinkedPostCount,
    poa.DuplicateLinkCount,
    rp.PostStatus,
    rp.Tags,
    CASE
        WHEN rp.PostScore > 100 AND rp.AnswerCount > 5 AND rp.CommentCount < 10 THEN 'High Engagement, Low Comment'
        WHEN rp.PostScore < 0 AND rp.PostTypeId = 1 THEN 'Low Score Question'
        WHEN rp.PostTypeId = 2 AND rp.PostScore > 50 THEN 'Highly Scored Answer'
        WHEN rp.Tags IS NULL THEN 'No Tags'
        WHEN rp.Tags LIKE '%sql%' OR rp.Tags LIKE '%database%' THEN 'SQL/DB Related Tag'
        ELSE 'Other'
    END AS PostCategory,
    CASE
        WHEN ua.UserViews > 1000000 AND ua.Reputation > 50000 THEN 'Highly Reputable User'
        WHEN ua.UserCreationDate < (cast('2024-10-01' as date) - INTERVAL '5 years') AND ua.Reputation < 1000 THEN 'Long Time Low Rep User'
        ELSE 'Standard User'
    END AS UserTier
FROM RankedPosts rp
JOIN PostTypes pt ON rp.PostTypeId = pt.Id
LEFT JOIN UserAggregates ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN PostActivity pa ON rp.PostId = pa.PostId
LEFT JOIN CommentStats cs ON rp.PostId = cs.PostId
LEFT JOIN PostLinkAnalysis poa ON rp.PostId = poa.PostId
WHERE rp.RowNum <= 100
ORDER BY rp.PostCreationDate DESC;