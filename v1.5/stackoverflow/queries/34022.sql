WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        u.Id AS OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY t.Id ORDER BY p.Score DESC) AS RankByScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1

    UNION ALL

    SELECT
        r.Id,
        r.TagName,
        pl.RelatedPostId AS PostId,
        p2.Title,
        p2.Score,
        p2.ViewCount,
        u2.Id AS OwnerUserId,
        u2.DisplayName AS OwnerDisplayName,
        r.RankByScore + 1
    FROM RecursiveTagHierarchy r
    JOIN PostLinks pl ON pl.PostId = r.PostId AND pl.LinkTypeId = 1
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId AND p2.PostTypeId = 1
    JOIN Users u2 ON u2.Id = p2.OwnerUserId
    WHERE r.RankByScore < 10
)
SELECT
    rh.TagName,
    rh.PostId,
    rh.Title,
    rh.Score,
    rh.ViewCount,
    rh.OwnerUserId,
    rh.OwnerDisplayName,
    COALESCE(badges.GoldBadges, 0) AS GoldBadges,
    COALESCE(badges.SilverBadges, 0) AS SilverBadges,
    COALESCE(badges.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(commentStats.CommentCount, 0) AS CommentCount,
    COALESCE(voteStats.UpVotes, 0) AS UpVotes,
    COALESCE(voteStats.DownVotes, 0) AS DownVotes,
    ROUND(CAST(p.Score AS NUMERIC) / NULLIF(p.ViewCount, 0), 4) AS ScorePerView,
    u.Reputation
FROM RecursiveTagHierarchy rh
JOIN Posts p ON p.Id = rh.PostId
JOIN Users u ON u.Id = rh.OwnerUserId
LEFT JOIN (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
) badges ON badges.UserId = rh.OwnerUserId
LEFT JOIN (
    SELECT
        PostId,
        COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
) commentStats ON commentStats.PostId = rh.PostId
LEFT JOIN (
    SELECT
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
) voteStats ON voteStats.PostId = rh.PostId
WHERE rh.RankByScore <= 10
ORDER BY rh.TagName, rh.RankByScore;