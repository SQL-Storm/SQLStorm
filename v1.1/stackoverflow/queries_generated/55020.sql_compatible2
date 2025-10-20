WITH user_stats AS (
    SELECT
        u.Id                      AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id)      AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(p.Score)              AS TotalPostScore,
        SUM(p.ViewCount)          AS TotalPostViews,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesReceived,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesReceived,
        COUNT(DISTINCT b.Id)      AS BadgesEarned,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        MIN(u.CreationDate)       AS FirstSeen,
        MAX(u.LastAccessDate)     AS LastSeen
    FROM Users u
    LEFT JOIN Posts p       ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v       ON v.PostId = p.Id
    LEFT JOIN Badges b      ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
tag_activity AS (
    SELECT
        p.OwnerUserId                     AS UserId,
        tag                                 AS Tag,
        COUNT(*)                          AS TagUseCount,
        SUM(p.Score)                      AS TagScore,
        SUM(p.ViewCount)                  AS TagViews
    FROM Posts p,
         LATERAL (
             SELECT UNNEST(string_to_array(trim(BOTH '<>' FROM p.Tags), '><')) AS tag
         ) t
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, tag
),
top_tags AS (
    SELECT
        ta.UserId,
        ta.Tag,
        ta.TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY ta.UserId ORDER BY ta.TagUseCount DESC) AS rn
    FROM tag_activity ta
),
post_links_stats AS (
    SELECT
        p.OwnerUserId    AS UserId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateLinksCount
    FROM Posts p
    JOIN PostLinks pl ON pl.PostId = p.Id
    GROUP BY p.OwnerUserId
),
recent_activity AS (
    SELECT
        u.Id                AS UserId,
        COUNT(CASE WHEN ph.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days' THEN 1 END) AS RecentEdits,
        COUNT(CASE WHEN c.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days' THEN 1 END) AS RecentComments,
        COUNT(CASE WHEN v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days' AND v.VoteTypeId = 2 THEN 1 END) AS RecentUpvotes
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id
)
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalPosts,
    us.QuestionsAsked,
    us.AnswersGiven,
    us.TotalPostScore,
    us.TotalPostViews,
    us.UpVotesReceived,
    us.DownVotesReceived,
    us.BadgesEarned,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.FirstSeen,
    us.LastSeen,
    COALESCE(pl.LinkedPostsCount,0)            AS LinkedPostsCount,
    COALESCE(pl.DuplicateLinksCount,0)         AS DuplicateLinksCount,
    COALESCE(ra.RecentEdits,0)                 AS RecentEdits30d,
    COALESCE(ra.RecentComments,0)              AS RecentComments30d,
    COALESCE(ra.RecentUpvotes,0)               AS RecentUpvotes30d,
    STRING_AGG(tt.Tag || ':' || tt.TagUseCount, ', ') FILTER (WHERE tt.rn <= 3) AS Top3Tags
FROM user_stats us
LEFT JOIN post_links_stats pl      ON pl.UserId = us.UserId
LEFT JOIN recent_activity ra      ON ra.UserId = us.UserId
LEFT JOIN top_tags tt             ON tt.UserId = us.UserId
GROUP BY
    us.UserId, us.DisplayName, us.Reputation, us.TotalPosts,
    us.QuestionsAsked, us.AnswersGiven, us.TotalPostScore, us.TotalPostViews,
    us.UpVotesReceived, us.DownVotesReceived, us.BadgesEarned,
    us.GoldBadges, us.SilverBadges, us.BronzeBadges,
    us.FirstSeen, us.LastSeen,
    pl.LinkedPostsCount, pl.DuplicateLinksCount,
    ra.RecentEdits, ra.RecentComments, ra.RecentUpvotes
ORDER BY us.Reputation DESC
LIMIT 100;