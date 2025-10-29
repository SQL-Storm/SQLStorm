WITH RankedPostHistory AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.Comment,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
LatestPostEdits AS (
    SELECT
        rph.PostId,
        rph.UserId AS LastEditorUserId,
        rph.CreationDate AS LastEditDate,
        p.OwnerUserId
    FROM RankedPostHistory rph
    JOIN Posts p ON rph.PostId = p.Id
    WHERE rph.rn = 1
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AverageScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        CASE
            WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
            WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
            ELSE 'External Website'
        END AS WebsiteCategory
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.WebsiteUrl
),
PostVoteSummary AS (
    SELECT
        p.Id AS PostId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN v.Id END) AS UpVotes,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN v.Id END) AS DownVotes,
        COUNT(CASE WHEN vt.Name = 'Favorite' THEN v.Id END) AS Favorites
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY p.Id
)
SELECT
    p.Id AS PostId,
    pt.Name AS PostType,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate,
    p.LastActivityDate,
    p.ClosedDate,
    p.CommunityOwnedDate,
    u.DisplayName AS OwnerDisplayName,
    ue.DisplayName AS LastEditorDisplayName,
    lpe.LastEditDate,
    COALESCE(pvs.UpVotes, 0) AS TotalUpVotes,
    COALESCE(pvs.DownVotes, 0) AS TotalDownVotes,
    COALESCE(pvs.Favorites, 0) AS TotalFavorites,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.Score > 50 AND p.AnswerCount > 10 THEN 'Popular'
        WHEN p.AnswerCount > 5 AND p.ViewCount > 1000 THEN 'High Engagement'
        ELSE 'Standard'
    END AS PostStatusCategory,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) THEN 'Linked As Duplicate'
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 3) THEN 'Is Duplicate Of'
        ELSE 'Not Linked As Duplicate'
    END AS DuplicateStatus,
    up.TotalPosts AS OwnerTotalPosts,
    up.QuestionCount AS OwnerQuestionCount,
    up.AnswerCount AS OwnerAnswerCount,
    up.AverageScore AS OwnerAverageScore,
    up.BadgeCount AS OwnerBadgeCount,
    up.WebsiteCategory AS OwnerWebsiteCategory
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN LatestPostEdits lpe ON p.Id = lpe.PostId
LEFT JOIN Users ue ON lpe.LastEditorUserId = ue.Id
LEFT JOIN UserPostActivity up ON u.Id = up.UserId
LEFT JOIN PostVoteSummary pvs ON p.Id = pvs.PostId
WHERE p.Score > 0
  AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '365 days')
  AND (p.Title IS NOT NULL OR p.Tags IS NOT NULL)
  AND EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5)
GROUP BY
    p.Id,
    pt.Name,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate,
    p.LastActivityDate,
    p.ClosedDate,
    p.CommunityOwnedDate,
    u.DisplayName,
    ue.DisplayName,
    lpe.LastEditDate,
    pvs.UpVotes,
    pvs.DownVotes,
    pvs.Favorites,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.Score,
    p.AnswerCount,
    p.ViewCount,
    up.TotalPosts,
    up.QuestionCount,
    up.AnswerCount,
    up.AverageScore,
    up.BadgeCount,
    up.WebsiteCategory
ORDER BY p.LastActivityDate DESC
LIMIT 1000;