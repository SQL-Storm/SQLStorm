WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        p.OwnerUserId,
        LAG(p.ViewCount, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= DATE_TRUNC('month', CAST('2024-10-01 12:34:56' AS TIMESTAMP)) - INTERVAL '1 year'
), UserStats AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        COUNT(rp.PostId) AS PostCount,
        COUNT(CASE WHEN b.Id IS NOT NULL THEN 1 END) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
    FROM
        Users u
    LEFT JOIN
        RankedPosts rp ON u.Id = rp.OwnerUserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        Votes v ON rp.PostId = v.PostId
    GROUP BY
        u.Id, u.Reputation
), RecentComments AS (
    SELECT
        c.PostId,
        c.Text AS CommentText,
        c.CreationDate AS CommentDate,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS CommentRank
    FROM
        Comments c
    WHERE
        c.CreationDate >= DATE_TRUNC('month', CAST('2024-10-01 12:34:56' AS TIMESTAMP)) - INTERVAL '3 months'
), PostStats AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    WHERE
        p.PostTypeId = 1
    GROUP BY
        p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount
), CombinedData AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CreationDate,
        rp.PrevViewCount,
        rp.PostRank,
        rp.OwnerUserId,
        us.UserId,
        us.Reputation,
        us.PostCount,
        us.BadgeCount,
        us.GoldBadges,
        us.UpVotesReceived,
        us.DownVotesReceived,
        rc.CommentText,
        rc.CommentDate,
        rc.CommentRank,
        ps.VoteCount,
        ps.CommentCount,
        ps.LastEditDate
    FROM
        RankedPosts rp
    JOIN
        UserStats us ON rp.OwnerUserId = us.UserId
    LEFT JOIN
        RecentComments rc ON rp.PostId = rc.PostId AND rc.CommentRank = 1
    LEFT JOIN
        PostStats ps ON rp.PostId = ps.PostId
)
SELECT
    cd.PostId,
    cd.Title,
    cd.ViewCount,
    cd.AnswerCount,
    cd.CreationDate,
    cd.PrevViewCount,
    cd.PostRank,
    cd.UserId,
    cd.Reputation,
    cd.PostCount,
    cd.BadgeCount,
    cd.GoldBadges,
    cd.UpVotesReceived,
    cd.DownVotesReceived,
    cd.CommentText,
    cd.CommentDate,
    cd.CommentRank,
    cd.VoteCount,
    cd.CommentCount,
    cd.LastEditDate,
    CASE
        WHEN cd.PostRank <= 5 THEN 'Top Post'
        WHEN cd.PostRank <= 10 THEN 'Popular Post'
        ELSE 'Other Post'
    END AS PostCategory,
    CASE
        WHEN cd.Reputation >= 10000 THEN 'High Rep'
        WHEN cd.Reputation >= 1000 THEN 'Medium Rep'
        ELSE 'Low Rep'
    END AS UserRepCategory,
    CASE
        WHEN cd.AnswerCount > 10 THEN 'High Engagement'
        WHEN cd.AnswerCount > 5 THEN 'Medium Engagement'
        ELSE 'Low Engagement'
    END AS EngagementLevel,
    LENGTH(cd.Title) AS TitleLength,
    CASE
        WHEN cd.Title LIKE '%SQL%' THEN 'SQL Related'
        WHEN cd.Title LIKE '%JavaScript%' THEN 'JavaScript Related'
        ELSE 'Other'
    END AS TitleCategory
FROM
    CombinedData cd
WHERE
    cd.CreationDate >= DATE_TRUNC('month', CAST('2024-10-01 12:34:56' AS TIMESTAMP)) - INTERVAL '6 months'
    AND (cd.ViewCount > 100 OR cd.AnswerCount > 5)
ORDER BY
    cd.PostRank,
    cd.ViewCount DESC,
    cd.AnswerCount DESC;