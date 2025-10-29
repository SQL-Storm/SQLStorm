-- {"query": "3374.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1831} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, '[unknown]') AS Location,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
TopBadge AS (
    SELECT 
        b.UserId,
        STRING_AGG(b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadges,
        STRING_AGG(b.Name, ', ') FILTER (WHERE b.Class = 2) AS SilverBadges,
        STRING_AGG(b.Name, ', ') FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
RecentComments AS (
    SELECT 
        c.UserId,
        COUNT(*) AS RecentCommentCount
    FROM Comments c
    WHERE c.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY c.UserId
),
TagActivity AS (
    SELECT 
        p.OwnerUserId AS UserId,
        t.TagName,
        COUNT(*) AS TagPosts
    FROM Posts p
    JOIN LATERAL regexp_split_to_table(p.Tags, '[><]') AS tag(tag) ON TRUE
    JOIN Tags t ON t.TagName = tag.tag
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId, t.TagName
),
UserRank AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        tb.GoldBadges,
        tb.SilverBadges,
        tb.BronzeBadges,
        rc.RecentCommentCount,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.AnswerCount DESC) AS RankPos
    FROM UserStats us
    LEFT JOIN TopBadge tb ON tb.UserId = us.Id
    LEFT JOIN RecentComments rc ON rc.UserId = us.Id
    WHERE us.Reputation > 1000
)
SELECT
    ur.RankPos,
    ur.Id,
    ur.DisplayName,
    ur.Reputation,
    ur.QuestionCount,
    ur.AnswerCount,
    COALESCE(ur.GoldBadges, '') AS GoldBadges,
    COALESCE(ur.SilverBadges, '') AS SilverBadges,
    COALESCE(ur.BronzeBadges, '') AS BronzeBadges,
    COALESCE(ur.RecentCommentCount, 0) AS RecentComments,
    STRING_AGG(DISTINCT ta.TagName || ':' || ta.TagPosts::text, '; ') 
        FILTER (WHERE ta.TagPosts > 5) AS ActiveTags
FROM UserRank ur
LEFT JOIN TagActivity ta ON ta.UserId = ur.Id
GROUP BY 
    ur.RankPos, ur.Id, ur.DisplayName, ur.Reputation,
    ur.QuestionCount, ur.AnswerCount,
    ur.GoldBadges, ur.SilverBadges, ur.BronzeBadges,
    ur.RecentCommentCount
HAVING COUNT(*) > 0
ORDER BY ur.RankPos
LIMIT 50
UNION ALL
SELECT
    NULL, NULL, '--- Summary ---', NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL
;