WITH 
UserPostAgg AS (
    SELECT 
        u.Id                              AS UserId,
        COUNT(p.Id)                       AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        SUM(p.Score)                      AS TotalScore,
        MAX(p.CreationDate)               AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
UserBadgeAgg AS (
    SELECT 
        b.UserId,
        COUNT(*)                                 AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ',')         AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteStats AS (
    SELECT 
        p.OwnerUserId                           AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesGiven
    FROM Votes v
    JOIN Posts p ON p.Id = v.PostId
    GROUP BY p.OwnerUserId
),
UserCommentStats AS (
    SELECT 
        c.UserId,
        COUNT(*)                                 AS CommentCount,
        MAX(c.CreationDate)                      AS LastCommentDate
    FROM Comments c
    GROUP BY c.UserId
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count                                 AS TagUseCount,
        COALESCE(LENGTH(p_ex.Body),0)           AS ExcerptLength,
        COALESCE(LENGTH(p_wk.Body),0)           AS WikiLength,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    LEFT JOIN Posts p_ex ON p_ex.Id = t.ExcerptPostId
    LEFT JOIN Posts p_wk ON p_wk.Id = t.WikiPostId
),
RecentClosedDuplicates AS (
    SELECT 
        ph.PostId,
        ph.CreationDate,
        ph.Comment                               AS CloseReasonJson,
        ARRAY_AGG(pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateOfIds
    FROM PostHistory ph
    LEFT JOIN PostLinks pl 
        ON pl.PostId = ph.PostId AND pl.LinkTypeId = 3
    WHERE ph.PostHistoryTypeId = 10
      AND ph.Comment ~ '^\d+$'
    GROUP BY ph.PostId, ph.CreationDate, ph.Comment
)
SELECT *
FROM (
    SELECT
        u.Id                                            AS UserId,
        COALESCE(u.DisplayName,'Anonymous')             AS DisplayName,
        COALESCE(up.TotalPosts,0)                       AS TotalPosts,
        COALESCE(up.Questions,0)                        AS Questions,
        COALESCE(up.Answers,0)                          AS Answers,
        COALESCE(up.TotalScore,0)                       AS TotalScore,
        COALESCE(ub.BadgeCount,0)                       AS BadgeCount,
        COALESCE(ub.GoldBadges,0)                       AS GoldBadges,
        COALESCE(ub.SilverBadges,0)                     AS SilverBadges,
        COALESCE(ub.BronzeBadges,0)                     AS BronzeBadges,
        ub.BadgeNames,
        COALESCE(uv.UpVotesGiven,0)                     AS UpVotesGiven,
        COALESCE(uv.DownVotesGiven,0)                   AS DownVotesGiven,
        COALESCE(uv.FavoritesGiven,0)                   AS FavoritesGiven,
        COALESCE(uc.CommentCount,0)                     AS CommentCount,
        uc.LastCommentDate,
        CASE 
            WHEN COALESCE(up.TotalPosts,0) > 0 THEN ROUND(CAST(COALESCE(up.TotalScore,0) AS numeric) / COALESCE(up.TotalPosts,0),2)
            ELSE 0
        END                                            AS AvgScorePerPost,
        ('https://stackoverflow.com/users/' || CAST(u.Id AS varchar))    AS ProfileUrl,
        ROW_NUMBER() OVER (ORDER BY COALESCE(up.TotalScore,0) DESC)      AS GlobalRank,
        (SELECT COUNT(*) FROM Posts p 
            WHERE p.OwnerUserId = u.Id 
              AND p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days') AS PostsLast30Days,
        (SELECT COUNT(*) FROM Comments c 
            WHERE c.UserId = u.Id 
              AND c.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days') AS CommentsLast30Days,
        (SELECT STRING_AGG(DISTINCT tp.TagName, ',') 
            FROM TagPopularity tp 
            WHERE tp.TagRank <= 10)                     AS Top10Tags,
        1 AS sort_group,
        ROW_NUMBER() OVER (ORDER BY COALESCE(up.TotalScore,0) DESC)      AS rn_within_group
    FROM Users u
    LEFT JOIN UserPostAgg up   ON up.UserId = u.Id
    LEFT JOIN UserBadgeAgg ub  ON ub.UserId = u.Id
    LEFT JOIN UserVoteStats uv ON uv.UserId = u.Id
    LEFT JOIN UserCommentStats uc ON uc.UserId = u.Id
    WHERE u.Reputation >= 1000
      AND (up.TotalPosts IS NOT NULL OR ub.BadgeCount IS NOT NULL)
    ORDER BY COALESCE(up.TotalScore,0) DESC
    LIMIT 100
) t

UNION ALL

SELECT *
FROM (
    SELECT
        NULL                                            AS UserId,
        'SUMMARY'                                       AS DisplayName,
        SUM(COALESCE(up.TotalPosts,0))                  AS TotalPosts,
        SUM(COALESCE(up.Questions,0))                   AS Questions,
        SUM(COALESCE(up.Answers,0))                     AS Answers,
        SUM(COALESCE(up.TotalScore,0))                  AS TotalScore,
        SUM(COALESCE(ub.BadgeCount,0))                  AS BadgeCount,
        SUM(COALESCE(ub.GoldBadges,0))                  AS GoldBadges,
        SUM(COALESCE(ub.SilverBadges,0))                AS SilverBadges,
        SUM(COALESCE(ub.BronzeBadges,0))                AS BronzeBadges,
        NULL                                            AS BadgeNames,
        SUM(COALESCE(uv.UpVotesGiven,0))                AS UpVotesGiven,
        SUM(COALESCE(uv.DownVotesGiven,0))              AS DownVotesGiven,
        SUM(COALESCE(uv.FavoritesGiven,0))              AS FavoritesGiven,
        SUM(COALESCE(uc.CommentCount,0))                AS CommentCount,
        MAX(uc.LastCommentDate)                         AS LastCommentDate,
        NULL                                            AS AvgScorePerPost,
        NULL                                            AS ProfileUrl,
        NULL                                            AS GlobalRank,
        NULL                                            AS PostsLast30Days,
        NULL                                            AS CommentsLast30Days,
        NULL                                            AS Top10Tags,
        2 AS sort_group,
        NULL AS rn_within_group
    FROM UserPostAgg up
    LEFT JOIN UserBadgeAgg ub   ON ub.UserId = up.UserId
    LEFT JOIN UserVoteStats uv  ON uv.UserId = up.UserId
    LEFT JOIN UserCommentStats uc ON uc.UserId = up.UserId
    WHERE up.TotalPosts IS NOT NULL
) s
ORDER BY sort_group, rn_within_group NULLS LAST;