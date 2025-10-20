-- {"query": "139.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1302} 
WITH
recent_activity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS PostsCreated,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
        COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesGiven,
        MAX(p.LastActivityDate) AS LastPostActivity
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id
),
badge_impact AS (
    SELECT
        b.UserId,
        COUNT(*) AS BadgesEarned,
        STRING_AGG(b.Name, ',') AS BadgeNames,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
recent_mentions AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) AS PostsMentionedIn
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId = 50 -- CommunityBump events
    GROUP BY p.OwnerUserId
),
top_sets AS (
    SELECT
        nu.UserId,
        nu.DisplayName,
        nu.Reputation,
        nu.PostsCreated,
        nu.CommentsMade,
        nu.UpvotesGiven,
        nu.DownvotesGiven,
        COALESCE(br.BadgeNames, '') AS Badges,
        COALESCE(br.GoldBadges, 0) AS GoldBadges,
        COALESCE(br.SilverBadges, 0) AS SilverBadges,
        COALESCE(br.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(rm.PostsMentionedIn, 0) AS PostsMentionedIn,
        ROW_NUMBER() OVER (
            ORDER BY
                nu.Reputation DESC,
                nu.PostsCreated DESC,
                nu.UpvotesGiven DESC,
                nu.CommentsMade DESC
        ) AS rn
    FROM recent_activity nu
    LEFT JOIN badge_impact br ON br.UserId = nu.UserId
    LEFT JOIN recent_mentions rm ON rm.UserId = nu.UserId
),
tag_interest AS (
    SELECT
        u.Id AS UserId,
        t.TagName,
        COUNT(*) AS TagWatchCount,
        MAX(p.CreationDate) AS LastTagPostDate
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    JOIN UNNEST(string_to_array(p.Tags, '><')) AS t(TagName)
        ON TRUE
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, t.TagName
),
final_union AS (
    -- dataset 1: top users by reputation with activity and badges
    SELECT
        ts.UserId,
        ts.DisplayName,
        ts.Reputation AS metric1,
        ts.PostsCreated,
        ts.CommentsMade,
        ts.UpvotesGiven,
        ts.DownvotesGiven,
        ts.Badges,
        ts.GoldBadges,
        ts.SilverBadges,
        ts.BronzeBadges,
        ts.PostsMentionedIn,
        ts.rn,
        NULL::text AS tag_interest
    FROM top_sets ts
    WHERE ts.rn <= 100
    UNION ALL
    -- dataset 2: users with high tag diversity, including a correlated subquery for most recent tag
    SELECT
        fu.UserId,
        fu.DisplayName,
        fu.metric1,
        fu.PostsCreated,
        fu.CommentsMade,
        fu.UpvotesGiven,
        fu.DownvotesGiven,
        fu.Badges,
        fu.GoldBadges,
        fu.SilverBadges,
        fu.BronzeBadges,
        fu.PostsMentionedIn,
        fu.rn,
        ti.TagName AS tag_interest
    FROM (
        SELECT
            u.Id AS UserId,
            u.DisplayName,
            r.Reputation,
            r.PostsCreated,
            r.CommentsMade,
            r.UpvotesGiven,
            r.DownvotesGiven,
            b.Badges AS Badges,
            b.GoldBadges,
            b.SilverBadges,
            b.BronzeBadges,
            m.PostsMentionedIn,
            m.rn
        FROM top_sets r
        LEFT JOIN badge_impact b ON b.UserId = r.UserId
        LEFT JOIN recent_mentions m ON m.UserId = r.UserId
        WHERE r.rn <= 100
    ) fu
    JOIN tag_interest ti ON ti.UserId = fu.UserId
    WHERE ti.TagName IS NOT NULL
)
SELECT
    UserId,
    DisplayName,
    metric1,
    PostsCreated,
    CommentsMade,
    UpvotesGiven,
    DownvotesGiven,
    Badges,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    PostsMentionedIn,
    rn,
    tag_interest
FROM final_union
ORDER BY rn ASC
LIMIT 150;