-- {"query": "42.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 984} 
WITH
BestOfPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.OwnerDisplayName,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        AVG(v.BountyAmount) OVER (PARTITION BY p.Id) AS AvgBounty,
        COUNT(DISTINCT c.Id) OVER (PARTITION BY p.Id) AS CommentVol,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_by_owner
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 6 /* Close votes, left for correlation demonstration */
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId IN (1,2) -- Questions and Answers
      AND p.CreationDate >= NOW() - INTERVAL '2 years'
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.ProfileImageUrl,
        u.Location,
        u.AboutMe,
        u.AccountId,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1) AS QuestionCount
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes,
             u.ProfileImageUrl, u.Location, u.AboutMe, u.AccountId
),
JoinedStats AS (
    SELECT
        b.UserId,
        MAX(b.GoldBadges) AS GoldMax,
        MAX(b.SilverBadges) AS SilverMax,
        MAX(b.BronzeBadges) AS BronzeMax,
        SUM(CASE WHEN p.OwnerUserId IS NULL THEN 0 ELSE 1 END) AS PostsWithOwners
    FROM UserActivity b
    LEFT JOIN Posts p ON p.OwnerUserId = b.UserId
    GROUP BY b.UserId
),
ComplexSet AS (
    SELECT
        bop.PostId,
        bop.Title,
        bop.Tags,
        bop.PostTypeId,
        bop.Score,
        bop.ViewCount,
        bop.CreationDate,
        bop.LastActivityDate,
        bop.OwnerUserId,
        bop.OwnerDisplayName,
        bop.CommentCount,
        bop.FavoriteCount,
        bop.AcceptedAnswerId,
        bop.AvgBounty,
        bop.CommentVol,
        bop.rn_by_owner,
        ua.UserId AS ActivityUserId,
        ua.Reputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.QuestionCount,
        ws.LastLoginWindow
    FROM BestOfPosts bop
    CROSS JOIN JoinedStats js
    LEFT JOIN Users u ON u.Id = bop.OwnerUserId
    LEFT JOIN LATERAL (
        SELECT MAX(COALESCE(p2.LastActivityDate, bop.LastActivityDate)) AS LastLoginWindow
        FROM Posts p2
        WHERE p2.OwnerUserId = bop.OwnerUserId
    ) ws ON TRUE
    LEFT JOIN UserActivity ua ON ua.UserId = bop.OwnerUserId
)
SELECT
    PostId,
    Title,
    Tags,
    PostTypeId,
    Score,
    ViewCount,
    CreationDate,
    LastActivityDate,
    OwnerUserId,
    OwnerDisplayName,
    CommentCount,
    FavoriteCount,
    AcceptedAnswerId,
    AvgBounty,
    CommentVol,
    rn_by_owner,
    ActivityUserId,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    QuestionCount,
    LastLoginWindow
FROM ComplexSet
WHERE
    PostTypeId = 1 -- focus on questions
    AND Score > 0
    AND (CommentVol > 5 OR LastActivityDate > NOW() - INTERVAL '14 days')
ORDER BY Score DESC, ViewCount DESC
LIMIT 100;