WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        p.OwnerUserId,
        p.LastEditorUserId,
        p.Tags,
        u.Reputation AS OwnerReputation,
        u.DisplayName AS OwnerDisplayName,
        e.DisplayName AS LastEditorDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS Rank
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Users e ON p.LastEditorUserId = e.Id
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
),
TopPosts AS (
    SELECT
        PostId,
        Title,
        ViewCount,
        AnswerCount,
        CreationDate,
        OwnerUserId,
        OwnerReputation,
        OwnerDisplayName,
        LastEditorUserId,
        LastEditorDisplayName,
        Tags,
        ROW_NUMBER() OVER (ORDER BY ViewCount DESC) AS GlobalRank
    FROM
        RankedPosts
    WHERE
        Rank <= 10
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
        Badges b
    GROUP BY
        b.UserId
),
ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.DisplayName,
        u.LastAccessDate,
        COALESCE(ub.BadgeCount, 0) AS BadgeCount,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        COUNT(p.Id) AS PostCount,
        COUNT(DISTINCT p.Id) AS UniquePostCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        UserBadges ub ON u.Id = ub.UserId
    WHERE
        u.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.LastAccessDate,
        ub.BadgeCount, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
)
SELECT
    a.UserId,
    a.DisplayName,
    a.Reputation,
    a.UserCreationDate,
    a.LastAccessDate,
    a.BadgeCount,
    a.GoldBadges,
    a.SilverBadges,
    a.BronzeBadges,
    a.PostCount,
    a.UniquePostCount,
    a.LastPostDate,
    tp.PostId,
    tp.Title,
    tp.ViewCount,
    tp.AnswerCount,
    tp.CreationDate AS PostCreationDate,
    tp.GlobalRank,
    STRING_AGG(t.TagName, ', ') AS TagNames,
    COALESCE(p.Body, '') AS PostBody,
    COALESCE(tp.OwnerDisplayName, 'Unknown') AS PostOwnerDisplayName,
    COALESCE(tp.LastEditorDisplayName, 'Unknown') AS PostLastEditorDisplayName,
    COALESCE(p.LastEditDate, TIMESTAMP '1970-01-01') AS PostLastEditDate,
    c.Score AS CommentScore,
    c.Text AS CommentText,
    c.CreationDate AS CommentCreationDate
FROM
    ActiveUsers a
LEFT JOIN
    TopPosts tp ON a.UserId = tp.OwnerUserId
LEFT JOIN
    Posts p ON tp.PostId = p.Id
LEFT JOIN
    Comments c ON tp.PostId = c.PostId
LEFT JOIN (
    SELECT
        p1.Id AS PostId,
        -- normalize tags like "<tag1><tag2>" into separate rows; implementation varies by dialect
        -- here we split on '><' and trim leading '<' and trailing '>'
        TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM value)) AS TagName
    FROM
        Posts p1,
        LATERAL (
            -- split string into rows; try standard regexp_split_to_table for Postgres, fallback to JSON method in other systems
            SELECT regexp_split_to_table(p1.Tags, '><') AS value
        ) s
) t ON p.Id = t.PostId
WHERE
    tp.GlobalRank <= 50
GROUP BY
    a.UserId,
    a.DisplayName,
    a.Reputation,
    a.UserCreationDate,
    a.LastAccessDate,
    a.BadgeCount,
    a.GoldBadges,
    a.SilverBadges,
    a.BronzeBadges,
    a.PostCount,
    a.UniquePostCount,
    a.LastPostDate,
    tp.PostId,
    tp.Title,
    tp.ViewCount,
    tp.AnswerCount,
    tp.CreationDate,
    tp.GlobalRank,
    tp.OwnerDisplayName,
    tp.LastEditorDisplayName,
    p.Body,
    p.LastEditDate,
    c.Score,
    c.Text,
    c.CreationDate
ORDER BY
    a.Reputation DESC,
    tp.ViewCount DESC;