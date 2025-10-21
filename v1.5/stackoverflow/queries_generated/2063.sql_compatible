WITH RecentPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        u.DisplayName AS OwnerName,
        COUNT(c.Id) AS CommentCount
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE
        p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY
        p.Id, p.Title, p.CreationDate, p.Score, u.DisplayName
),
HighScoreComments AS (
    SELECT
        PostId,
        MAX(Score) AS MaxCommentScore
    FROM
        Comments
    GROUP BY
        PostId
),
BadgeCounts AS (
    SELECT
        CAST(UserId AS VARCHAR) AS UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM
        Badges
    GROUP BY
        CAST(UserId AS VARCHAR)
)
SELECT
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.OwnerName,
    rp.CommentCount,
    COALESCE(hc.MaxCommentScore, 0) AS MaxCommentScore,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges
FROM
    RecentPosts rp
LEFT JOIN
    HighScoreComments hc ON rp.Id = hc.PostId
LEFT JOIN
    BadgeCounts bc ON rp.OwnerName = bc.UserId
WHERE
    rp.Score > 100
ORDER BY
    rp.Score DESC, rp.CreationDate DESC;