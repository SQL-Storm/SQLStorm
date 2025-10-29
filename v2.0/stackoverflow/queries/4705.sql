WITH PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostType,
        COALESCE(p.Score, 0) AS PostScore,
        COALESCE(p.ViewCount, 0) AS PostViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
        COUNT(DISTINCT c.Id) AS CommentCountTotal,
        COUNT(DISTINCT v_up.Id) AS UpVoteCount,
        COUNT(DISTINCT v_down.Id) AS DownVoteCount,
        COUNT(DISTINCT v_fav.Id) AS FavoriteVoteCount,
        SUM(CASE WHEN v_down.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NegativeVotes,
        SUM(CASE WHEN v_up.VoteTypeId = 2 THEN 1 ELSE 0 END) AS PositiveVotes,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 1) AS LinkedToCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v_up ON p.Id = v_up.PostId AND v_up.VoteTypeId = 2
    LEFT JOIN Votes v_down ON p.Id = v_down.PostId AND v_down.VoteTypeId = 3
    LEFT JOIN Votes v_fav ON p.Id = v_fav.PostId AND v_fav.VoteTypeId = 5
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        pt.Name,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN LENGTH(ph.Text) ELSE NULL END) AS AvgPostLength,
        SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEditCount,
        MAX(ph.CreationDate) AS LastHistoryEntryDate,
        CASE
            WHEN u.DisplayName LIKE '% %' THEN SUBSTRING(u.DisplayName FROM 1 FOR (POSITION(' ' IN u.DisplayName) - 1))
            WHEN u.DisplayName IS NOT NULL THEN u.DisplayName
            ELSE 'Anonymous'
        END AS FirstName,
        CASE
            WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
            WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
            ELSE 'External Website'
        END AS WebsiteCategory,
        CASE
            WHEN u.AboutMe IS NULL OR u.AboutMe = '' THEN 'No Bio'
            WHEN LENGTH(u.AboutMe) < 100 THEN 'Short Bio'
            ELSE 'Detailed Bio'
        END AS BioLengthCategory
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.WebsiteUrl,
        u.AboutMe
),
PostHistoryAnalysis AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 4, 7) THEN 1 ELSE 0 END) AS TitleChangeCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5, 8) THEN 1 ELSE 0 END) AS BodyChangeCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (3, 6, 9) THEN 1 ELSE 0 END) AS TagChangeCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (33, 34) THEN 1 ELSE 0 END) AS PostNoticeCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 24 THEN ph.UserId END) AS SuggestedEditApplyCount
    FROM PostHistory ph
    GROUP BY ph.PostId
)
SELECT
    pe.PostId,
    pe.Title,
    pe.PostType,
    pe.PostScore,
    pe.PostViewCount,
    pe.AnswerCount,
    pe.CommentCount,
    pe.FavoriteCount,
    pe.IsClosed,
    pe.IsCommunityOwned,
    pe.CommentCountTotal,
    pe.UpVoteCount,
    pe.DownVoteCount,
    pe.FavoriteVoteCount,
    pe.DuplicateLinkCount,
    pe.LinkedToCount,
    ua.DisplayName AS OwnerDisplayName,
    ua.Reputation AS OwnerReputation,
    ua.UserCreationDate AS OwnerCreationDate,
    ua.BadgeCount AS OwnerBadgeCount,
    ua.AvgPostLength AS OwnerAvgPostLength,
    ua.BodyEditCount AS OwnerBodyEditCount,
    ua.FirstName AS OwnerFirstName,
    ua.WebsiteCategory AS OwnerWebsiteCategory,
    ua.BioLengthCategory AS OwnerBioLengthCategory,
    pha.TotalHistoryEntries,
    pha.TitleChangeCount,
    pha.BodyChangeCount,
    pha.TagChangeCount,
    pha.CloseVoteCount,
    pha.PostNoticeCount,
    pha.SuggestedEditApplyCount,
    CASE
        WHEN pe.PostScore > 1000 THEN 'Very High Score'
        WHEN pe.PostScore > 100 THEN 'High Score'
        WHEN pe.PostScore > 0 THEN 'Positive Score'
        ELSE 'Non-Positive Score'
    END AS ScoreCategory,
    CASE
        WHEN pe.PostViewCount > 100000 THEN 'Very High Views'
        WHEN pe.PostViewCount > 10000 THEN 'High Views'
        ELSE 'Moderate Views'
    END AS ViewCountCategory,
    CASE
        WHEN pe.CommentCountTotal > 50 THEN 'High Comment Volume'
        WHEN pe.CommentCountTotal > 10 THEN 'Moderate Comment Volume'
        ELSE 'Low Comment Volume'
    END AS CommentVolumeCategory,
    CASE
        WHEN COALESCE(pha.TotalHistoryEntries,0) > 20 THEN 'Extensive Editing'
        WHEN COALESCE(pha.TotalHistoryEntries,0) > 5 THEN 'Moderate Editing'
        ELSE 'Minimal Editing'
    END AS EditingActivityCategory,
    EXTRACT(YEAR FROM pe.PostCreationDate) AS PostCreationYear,
    EXTRACT(MONTH FROM pe.PostCreationDate) AS PostCreationMonth,
    CASE
        WHEN EXTRACT(DOW FROM pe.PostCreationDate) IN (0, 6) THEN 'Weekend'
        ELSE 'Weekday'
    END AS PostCreationDayOfWeek,
    COALESCE(ua.LastHistoryEntryDate, ua.LastAccessDate) AS LastActivityRelevantDate
FROM PostEngagement pe
JOIN UserActivity ua ON pe.OwnerUserId = ua.UserId
LEFT JOIN PostHistoryAnalysis pha ON pe.PostId = pha.PostId
WHERE
    pe.PostType IN ('Question', 'Answer')
    AND ua.Reputation > 1000
    AND pe.PostScore > 0
    AND pha.TotalHistoryEntries IS NOT NULL
    AND UPPER(pe.Title) LIKE '%SQL%'
    AND COALESCE(ua.UserUpVotes, 0) > COALESCE(ua.UserDownVotes, 0) * 2
    AND pe.PostCreationDate >= DATE '2023-01-01'
UNION ALL
SELECT
    pe.PostId,
    pe.Title,
    pe.PostType,
    pe.PostScore,
    pe.PostViewCount,
    pe.AnswerCount,
    pe.CommentCount,
    pe.FavoriteCount,
    pe.IsClosed,
    pe.IsCommunityOwned,
    pe.CommentCountTotal,
    pe.UpVoteCount,
    pe.DownVoteCount,
    pe.FavoriteVoteCount,
    pe.DuplicateLinkCount,
    pe.LinkedToCount,
    ua.DisplayName AS OwnerDisplayName,
    ua.Reputation AS OwnerReputation,
    ua.UserCreationDate AS OwnerCreationDate,
    ua.BadgeCount AS OwnerBadgeCount,
    ua.AvgPostLength AS OwnerAvgPostLength,
    ua.BodyEditCount AS OwnerBodyEditCount,
    ua.FirstName AS OwnerFirstName,
    ua.WebsiteCategory AS OwnerWebsiteCategory,
    ua.BioLengthCategory AS OwnerBioLengthCategory,
    pha.TotalHistoryEntries,
    pha.TitleChangeCount,
    pha.BodyChangeCount,
    pha.TagChangeCount,
    pha.CloseVoteCount,
    pha.PostNoticeCount,
    pha.SuggestedEditApplyCount,
    CASE
        WHEN pe.PostScore > 1000 THEN 'Very High Score'
        WHEN pe.PostScore > 100 THEN 'High Score'
        WHEN pe.PostScore > 0 THEN 'Positive Score'
        ELSE 'Non-Positive Score'
    END AS ScoreCategory,
    CASE
        WHEN pe.PostViewCount > 100000 THEN 'Very High Views'
        WHEN pe.PostViewCount > 10000 THEN 'High Views'
        ELSE 'Moderate Views'
    END AS ViewCountCategory,
    CASE
        WHEN pe.CommentCountTotal > 50 THEN 'High Comment Volume'
        WHEN pe.CommentCountTotal > 10 THEN 'Moderate Comment Volume'
        ELSE 'Low Comment Volume'
    END AS CommentVolumeCategory,
    CASE
        WHEN COALESCE(pha.TotalHistoryEntries,0) > 20 THEN 'Extensive Editing'
        WHEN COALESCE(pha.TotalHistoryEntries,0) > 5 THEN 'Moderate Editing'
        ELSE 'Minimal Editing'
    END AS EditingActivityCategory,
    EXTRACT(YEAR FROM pe.PostCreationDate) AS PostCreationYear,
    EXTRACT(MONTH FROM pe.PostCreationDate) AS PostCreationMonth,
    CASE
        WHEN EXTRACT(DOW FROM pe.PostCreationDate) IN (0, 6) THEN 'Weekend'
        ELSE 'Weekday'
    END AS PostCreationDayOfWeek,
    COALESCE(ua.LastHistoryEntryDate, ua.LastAccessDate) AS LastActivityRelevantDate
FROM PostEngagement pe
JOIN UserActivity ua ON pe.OwnerUserId = ua.UserId
LEFT JOIN PostHistoryAnalysis pha ON pe.PostId = pha.PostId
WHERE
    pe.PostType = 'Question'
    AND ua.Reputation < 500
    AND pe.PostScore <= 0
    AND pha.TotalHistoryEntries IS NOT NULL
    AND UPPER(pe.Title) LIKE '%PYTHON%'
    AND COALESCE(ua.UserDownVotes, 0) > COALESCE(ua.UserUpVotes, 0)
    AND pe.PostCreationDate < DATE '2022-01-01'
    AND pe.AnswerCount < 2
ORDER BY LastActivityRelevantDate DESC, PostScore DESC;