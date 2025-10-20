-- {"query": "5073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1211} 
WITH TopActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        u.Location,
        COUNT(DISTINCT p.Id) AS PostCount,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC, u.Reputation DESC) AS UserRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.CreationDate, u.Location
    HAVING COUNT(p.Id) > 10
),
PostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(p.Score) AS AvgScore,
        MAX(p.ViewCount) AS MaxViews
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
RecentComments AS (
    SELECT
        c.UserId,
        COUNT(*) AS RecentCommentsCount
    FROM Comments c
    WHERE c.CreationDate >= NOW() - INTERVAL '30 day'
    GROUP BY c.UserId
),
BadgeAgg AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
LatestActivity AS (
    SELECT
        p.OwnerUserId,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentActivity
    FROM Posts p
    LEFT JOIN Comments c ON p.OwnerUserId = c.UserId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
HighScorePosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.Title
    FROM Posts p
    WHERE p.Score > (
        SELECT AVG(p2.Score)
        FROM Posts p2
        WHERE p2.PostTypeId IN (1,2)
            AND p2.OwnerUserId = p.OwnerUserId
            AND p2.Score IS NOT NULL
    )
),
UserTagPrefs AS (
    SELECT
        p.OwnerUserId,
        INITCAP(REGEXP_REPLACE(unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')), '\W', ' ', 'g')) AS PreferredTag
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.OwnerUserId IS NOT NULL
          AND p.PostTypeId = 1
)
SELECT
    tau.UserId,
    tau.DisplayName,
    tau.UserRank,
    tau.Reputation,
    tau.UpVotes,
    tau.DownVotes,
    tau.CreationDate,
    COALESCE(tau.Location, 'Unknown') AS Location,
    tau.PostCount,
    ps.TotalPosts,
    ps.Questions,
    ps.Answers,
    ps.AvgScore,
    ps.MaxViews,
    ra.RecentCommentsCount,
    ba.GoldBadges,
    ba.SilverBadges,
    ba.BronzeBadges,
    la.LastPostActivity,
    la.LastCommentActivity,
    STRING_AGG(DISTINCT up.PreferredTag, ', ' ORDER BY up.PreferredTag) AS SamplePreferredTags,
    COUNT(DISTINCT hp.Id) AS HighScorePosts,
    MAX(hp.Score) AS MaxHighScore,
    CASE
        WHEN SUM(CASE WHEN hp.Score > 50 THEN 1 ELSE 0 END) > 0 THEN 'SuperStar'
        WHEN ba.GoldBadges >= 3 THEN 'BadgeHunter'
        WHEN tau.UpVotes > tau.DownVotes * 2 THEN 'Helpful'
        ELSE 'Normal'
    END AS UserHighlight
FROM TopActiveUsers tau
LEFT JOIN PostStats ps ON tau.UserId = ps.OwnerUserId
LEFT JOIN RecentComments ra ON tau.UserId = ra.UserId
LEFT JOIN BadgeAgg ba ON tau.UserId = ba.UserId
LEFT JOIN LatestActivity la ON tau.UserId = la.OwnerUserId
LEFT JOIN HighScorePosts hp ON tau.UserId = hp.OwnerUserId
LEFT JOIN UserTagPrefs up ON tau.UserId = up.OwnerUserId
WHERE COALESCE(ba.GoldBadges,0) + COALESCE(ba.SilverBadges,0) + COALESCE(ba.BronzeBadges,0) > 0
GROUP BY
    tau.UserId,
    tau.DisplayName,
    tau.UserRank,
    tau.Reputation,
    tau.UpVotes,
    tau.DownVotes,
    tau.CreationDate,
    tau.Location,
    tau.PostCount,
    ps.TotalPosts,
    ps.Questions,
    ps.Answers,
    ps.AvgScore,
    ps.MaxViews,
    ra.RecentCommentsCount,
    ba.GoldBadges,
    ba.SilverBadges,
    ba.BronzeBadges,
    la.LastPostActivity,
    la.LastCommentActivity
HAVING
    MAX(hp.Score) IS NOT NULL
    AND COUNT(DISTINCT hp.Id) >= 2
ORDER BY
    tau.UserRank,
    tau.Reputation DESC
LIMIT 100;