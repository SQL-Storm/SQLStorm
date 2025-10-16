WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(b.BadgeCount, 0) AS BadgeCount,
        COALESCE(p.PostCount, 0) AS PostCount,
        COALESCE(c.CommentCount, 0) AS CommentCount,
        COALESCE(v.VoteCount, 0) AS VoteCount,
        RANK() OVER (ORDER BY COALESCE(b.BadgeCount, 0) DESC, COALESCE(p.PostCount, 0) DESC) AS UserRank
    FROM Users u
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount
        FROM Badges
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS PostCount
        FROM Posts
        WHERE PostTypeId IN (1, 2)
        GROUP BY OwnerUserId
    ) p ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS CommentCount
        FROM Comments
        WHERE UserId IS NOT NULL
        GROUP BY UserId
    ) c ON u.Id = c.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS VoteCount
        FROM Votes
        WHERE UserId IS NOT NULL
        GROUP BY UserId
    ) v ON u.Id = v.UserId
),
MaxBadges AS (
    SELECT
        MAX(BadgeCount) AS MaxBadgeCount
    FROM UserActivity
),
LinkAnalysis AS (
    SELECT
        pl.PostId,
        STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) AS AggregateTagNames
    FROM PostLinks pl
    JOIN Posts p ON pl.RelatedPostId = p.Id
    JOIN (
        SELECT p_inner.Id AS PostId, TRIM(tag) AS TagName
        FROM Posts p_inner,
        LATERAL (
            SELECT REGEXP_SPLIT_TO_TABLE(
                CASE
                    WHEN LEFT(COALESCE(p_inner.Tags, ''), 1) = '<' AND RIGHT(COALESCE(p_inner.Tags, ''), 1) = '>' THEN SUBSTRING(p_inner.Tags FROM 2 FOR (LENGTH(COALESCE(p_inner.Tags, '')) - 2))
                    ELSE COALESCE(p_inner.Tags, '')
                END,
                '><'
            ) AS tag
        ) s
    ) tag_table ON tag_table.PostId = p.Id
    JOIN Tags t ON t.TagName = tag_table.TagName
    GROUP BY pl.PostId
)
SELECT ua.UserId,
       ua.DisplayName,
       ua.BadgeCount,
       ua.PostCount,
       ua.CommentCount,
       ua.VoteCount,
       MaxBadges.MaxBadgeCount,
       COALESCE(la.AggregateTagNames, 'No Tags Linked') AS Tags,
       CASE
           WHEN ua.BadgeCount = MaxBadges.MaxBadgeCount THEN 'Top Badge Holder'
           ELSE 'Regular User'
       END AS Status,
       ua.UserRank
FROM UserActivity ua
JOIN MaxBadges ON 1 = 1
LEFT JOIN LinkAnalysis la ON ua.UserId = la.PostId
WHERE ua.BadgeCount > 0
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.BadgeCount,
    ua.PostCount,
    ua.CommentCount,
    ua.VoteCount,
    MaxBadges.MaxBadgeCount,
    la.AggregateTagNames,
    ua.UserRank;