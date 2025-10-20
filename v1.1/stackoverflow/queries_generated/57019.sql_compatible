WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(v.CreationDate) AS LastVoteDate,
        MAX(b.Date) AS LastBadgeDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate
),
HighActivityUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        TotalPosts,
        TotalComments,
        TotalVotes,
        TotalBadges,
        LastPostActivity,
        LastCommentDate,
        LastVoteDate,
        LastBadgeDate
    FROM
        UserActivity
    WHERE
        TotalPosts > 100 OR
        TotalComments > 50 OR
        TotalVotes > 100 OR
        TotalBadges > 10
),
RecentPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.UserId AS OwnerUserId_in_HAU,
        u.Reputation AS OwnerReputation_in_HAU,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.LastActivityDate
    FROM
        Posts p
    JOIN
        HighActivityUsers u ON p.OwnerUserId = u.UserId
    WHERE
        p.PostTypeId = 1 AND
        p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
),
PopularTags AS (
    SELECT
        t.TagName,
        COUNT(rp.PostId) AS TagUsageCount
    FROM
        Tags t
    JOIN
        RecentPosts rp ON rp.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    GROUP BY
        t.TagName
    ORDER BY
        TagUsageCount DESC
    LIMIT 20
),
TagActivity AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.OwnerUserId AS OwnerUserId,
        rp.OwnerUserId_in_HAU,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        pt.TagName,
        rp.LastActivityDate
    FROM
        RecentPosts rp
    JOIN
        PopularTags pt ON rp.Tags LIKE '%' || '<' || pt.TagName || '>' || '%'
    ORDER BY
        rp.Score DESC,
        rp.ViewCount DESC
    LIMIT 50
)
SELECT
    ta.PostId,
    ta.Title,
    -- OwnerDisplayName not available in HighActivityUsers; show OwnerUserId instead
    ta.OwnerUserId AS OwnerUserId,
    ta.Score,
    ta.ViewCount,
    ta.AnswerCount,
    ta.CommentCount,
    ta.TagName,
    ta.LastActivityDate,
    u.Reputation AS OwnerReputation,
    u.UserCreationDate,
    u.TotalPosts,
    u.TotalComments,
    u.TotalVotes,
    u.TotalBadges
FROM
    TagActivity ta
JOIN
    HighActivityUsers u ON ta.OwnerUserId = u.UserId
ORDER BY
    ta.Score DESC,
    ta.ViewCount DESC;