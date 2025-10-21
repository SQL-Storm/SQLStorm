WITH
RecentPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COALESCE(v.SumVote, 0) AS TotalUpDown
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, SUM(CASE WHEN VoteTypeId IN (2) THEN 1 ELSE 0 END) AS SumVote
        FROM Votes
        GROUP BY PostId
    ) v ON v.PostId = p.Id
    WHERE p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
    GROUP BY
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName,
        v.SumVote
),
WindowedPosts AS (
    SELECT
        rp.*,
        ROW_NUMBER() OVER (
            PARTITION BY rp.PostTypeId
            ORDER BY (rp.Score * 2.0 + rp.ViewCount * 0.5 + rp.CommentCount * 1.5 + rp.TotalUpDown) DESC
        ) AS rn_by_type,
        RANK() OVER (
            ORDER BY (rp.Score * 2.0 + rp.ViewCount * 0.5 + rp.CommentCount * 1.5 + rp.TotalUpDown) DESC
        ) AS overall_rank
    FROM RecentPosts rp
),
TagActivity AS (
    SELECT
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        d.DisplayName AS TagOwner
    FROM Tags t
    LEFT JOIN Posts e ON t.ExcerptPostId = e.Id
    LEFT JOIN Posts w ON t.WikiPostId = w.Id
    LEFT JOIN Users d ON e.OwnerUserId = d.Id
    WHERE t.IsModeratorOnly = FALSE
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(*) AS BadgeCountLastYear
    FROM Badges b
    WHERE b.Date >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365 days'
    GROUP BY b.UserId
),
DuplicateCheck AS (
    SELECT
        p.Id AS PostId,
        EXISTS (
            SELECT 1
            FROM PostLinks pl
            WHERE (pl.PostId = p.Id OR pl.RelatedPostId = p.Id)
              AND pl.LinkTypeId = 3
        ) AS HasDuplicateLink
    FROM Posts p
)
SELECT
    wp.PostId,
    wp.PostTypeId,
    pt.Name AS PostTypeName,
    wp.Title,
    wp.Tags,
    wp.CreationDate,
    wp.LastActivityDate,
    wp.Score,
    wp.ViewCount,
    wp.OwnerUserId,
    wp.OwnerDisplayName,
    wp.CommentCount,
    wp.TotalUpDown,
    tb.BadgeCountLastYear,
    dc.HasDuplicateLink,
    ta.TagName,
    ta.Count AS TagCount,
    ta.TagOwner
FROM WindowedPosts wp
LEFT JOIN PostTypes pt ON wp.PostTypeId = pt.Id
LEFT JOIN UserBadges tb ON wp.OwnerUserId = tb.UserId
LEFT JOIN DuplicateCheck dc ON wp.PostId = dc.PostId
LEFT JOIN TagActivity ta ON ta.TagName = ANY(string_to_array(SUBSTRING(wp.Tags FROM 2 FOR POSITION('>' IN wp.Tags) - 2), '><'))
WHERE wp.rn_by_type <= 50
GROUP BY
    wp.PostId,
    wp.PostTypeId,
    pt.Name,
    wp.Title,
    wp.Tags,
    wp.CreationDate,
    wp.LastActivityDate,
    wp.Score,
    wp.ViewCount,
    wp.OwnerUserId,
    wp.OwnerDisplayName,
    wp.CommentCount,
    wp.TotalUpDown,
    tb.BadgeCountLastYear,
    dc.HasDuplicateLink,
    ta.TagName,
    ta.Count,
    ta.TagOwner
UNION ALL
SELECT
    NULL AS PostId,
    NULL AS PostTypeId,
    NULL AS PostTypeName,
    NULL AS Title,
    NULL AS Tags,
    NULL AS CreationDate,
    NULL AS LastActivityDate,
    NULL AS Score,
    NULL AS ViewCount,
    NULL AS OwnerUserId,
    NULL AS OwnerDisplayName,
    NULL AS CommentCount,
    NULL AS TotalUpDown,
    NULL AS BadgeCountLastYear,
    NULL AS HasDuplicateLink,
    NULL AS TagName,
    NULL AS TagCount,
    NULL AS TagOwner
FROM generate_series(1,1);