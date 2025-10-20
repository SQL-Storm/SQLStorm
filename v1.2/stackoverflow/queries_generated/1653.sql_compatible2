WITH
UserBadgeStats AS (
    SELECT
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges,
        COUNT(*) FILTER (WHERE TagBased = TRUE) AS TagBasedBadges,
        COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
),
RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        RANK() OVER (
            PARTITION BY p.PostTypeId
            ORDER BY (
                p.Score * 5
                + COALESCE(p.FavoriteCount, 0) * 10
                + p.ViewCount / NULLIF(GREATEST(EXTRACT(day FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)), 1), 0)
            ) DESC
        ) AS PostRank,
        p.Title,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS DateRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
ActivePostComments AS (
    SELECT
        post.Id AS PostId,
        post.Title,
        "user".DisplayName AS OwnerName,
        post.Score,
        c.Id AS CommentId,
        c.Text,
        c.CreationDate AS CommentDate,
        U.DisplayName AS CommentUserName,
        c.UserId AS CommentUserId,
        COUNT(c2.Id) OVER (PARTITION BY post.Id) AS CommentCountOnPost
    FROM Posts post
    LEFT JOIN Comments c ON c.PostId = post.Id
    LEFT JOIN Comments c2 ON c2.PostId = post.Id
    LEFT JOIN Users U ON U.Id = c.UserId
    JOIN Users "user" ON "user".Id = post.OwnerUserId
    WHERE post.PostTypeId = 1
      AND post.Score >= (
          SELECT P50 FROM (
              SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Score) AS P50
              FROM Posts
              WHERE PostTypeId = 1
          ) q
      )
)
SELECT
    apc.PostId,
    apc.Title,
    apc.OwnerName,
    apc.Score,
    apc.CommentId,
    apc.Text,
    apc.CommentDate,
    apc.CommentUserName,
    apc.CommentUserId,
    apc.CommentCountOnPost,
    rb.PostTypeId,
    rb.OwnerUserId,
    rb.CreationDate,
    rb.PostRank,
    rb.DateRank,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TagBasedBadges,
    ub.TotalBadges
FROM ActivePostComments apc
LEFT JOIN RankedPosts rb ON rb.Id = apc.PostId
LEFT JOIN UserBadgeStats ub ON ub.UserId = rb.OwnerUserId
WHERE 1 = 1
ORDER BY apc.PostId, rb.PostRank;