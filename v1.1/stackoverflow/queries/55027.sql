WITH 
user_metrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVoteCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId = 10 THEN bh.Id END) AS ClosedPosts,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 15 THEN ph.Id END) AS ReopenedPosts
    FROM Users u
    LEFT JOIN Posts p 
        ON p.OwnerUserId = u.Id 
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '12 months'
    LEFT JOIN Comments c 
        ON c.UserId = u.Id 
        AND c.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '12 months'
    LEFT JOIN Votes v 
        ON v.UserId = u.Id 
        AND v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '12 months'
    LEFT JOIN Badges b 
        ON b.UserId = u.Id 
        AND b.Date >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '12 months'
    LEFT JOIN PostHistory ph 
        ON ph.UserId = u.Id 
        AND ph.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '12 months'
    LEFT JOIN PostHistory bh 
        ON bh.PostId = p.Id 
        AND bh.PostHistoryTypeId = 10
        AND bh.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '12 months'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
user_top_tag AS (
    SELECT 
        um.UserId,
        t.TagName,
        COUNT(*) AS TagUsage,
        ROW_NUMBER() OVER (PARTITION BY um.UserId ORDER BY COUNT(*) DESC) AS rn
    FROM user_metrics um
    JOIN Posts p 
        ON p.OwnerUserId = um.UserId 
        AND p.PostTypeId = 1
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag
    ) AS taglist
    JOIN Tags t 
        ON t.TagName = taglist.tag
    GROUP BY um.UserId, t.TagName
),
user_badge_breakdown AS (
    SELECT 
        u.Id AS UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
)
SELECT 
    um.UserId,
    um.DisplayName,
    um.Reputation,
    um.QuestionCount,
    um.AnswerCount,
    um.CommentCount,
    um.UpVoteCount,
    um.DownVoteCount,
    um.TotalQuestionScore,
    um.TotalAnswerScore,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ut.TagName AS TopTag,
    ut.TagUsage AS TopTagUsage,
    um.BadgeCount,
    um.ClosedPosts,
    um.ReopenedPosts,
    (um.QuestionCount * 4 + um.AnswerCount * 6 + um.CommentCount * 2
     + um.UpVoteCount * 1 - um.DownVoteCount * 2
     + COALESCE(ub.GoldBadges,0) * 10 + COALESCE(ub.SilverBadges,0) * 5 + COALESCE(ub.BronzeBadges,0)) 
    AS ActivityScore
FROM user_metrics um
LEFT JOIN user_badge_breakdown ub ON ub.UserId = um.UserId
LEFT JOIN (
    SELECT UserId, TagName, TagUsage
    FROM user_top_tag
    WHERE rn = 1
) ut ON ut.UserId = um.UserId
WHERE um.Reputation > 1000
ORDER BY ActivityScore DESC
LIMIT 100;