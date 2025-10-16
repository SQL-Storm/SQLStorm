-- {"query": "5039.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1185} 
WITH TopActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        ROW_NUMBER() OVER (ORDER BY (COUNT(DISTINCT p.Id) + COUNT(DISTINCT c.Id)) DESC, u.Reputation DESC) AS UserRank
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN Comments c ON c.UserId = u.Id
    WHERE
        u.Reputation > 1000
        AND (p.CreationDate > u.CreationDate OR p.CreationDate IS NULL)
        AND (c.CreationDate > u.CreationDate OR c.CreationDate IS NULL)
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
    HAVING
        COUNT(DISTINCT p.Id) + COUNT(DISTINCT c.Id) > 10
),
UserBadges AS (
    SELECT
        u.Id AS UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MIN(b.Date) AS FirstBadgeDate,
        MAX(b.Date) AS LastBadgeDate
    FROM
        Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY
        u.Id
),
UserRecentVotes AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetRecentVotes,
        COUNT(DISTINCT CASE WHEN v.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 day' THEN v.Id END) AS RecentVoteCount
    FROM
        Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE
        p.OwnerUserId IS NOT NULL
    GROUP BY
        p.OwnerUserId
),
TagEngagement AS (
    SELECT
        pu.UserId,
        t.TagName,
        COUNT(*) AS TagPostCount,
        ROW_NUMBER() OVER (PARTITION BY pu.UserId ORDER BY COUNT(*) DESC) AS rn
    FROM
        (
            SELECT OwnerUserId AS UserId, Id, Tags
            FROM Posts
            WHERE OwnerUserId IS NOT NULL
                AND PostTypeId IN (1,2)
                AND Tags IS NOT NULL
        ) pu,
        LATERAL (
            SELECT unnest(string_to_array(SUBSTRING(pu.Tags, 2, LENGTH(pu.Tags)-2), '><')) AS TagName
        ) t
    GROUP BY pu.UserId, t.TagName
),
MostPopularTag AS (
    SELECT
        UserId,
        TagName
    FROM TagEngagement
    WHERE rn = 1
),
UserClosedPosts AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS ClosedPostCount,
        MAX(p.ClosedDate) AS LastClosedPost
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.ClosedDate IS NOT NULL
    GROUP BY u.Id
)
SELECT
    tau.UserId,
    tau.DisplayName,
    tau.Reputation,
    tau.PostCount,
    tau.CommentCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.FirstBadgeDate,
    ub.LastBadgeDate,
    COALESCE(urv.NetRecentVotes, 0) AS NetRecentVotes,
    COALESCE(urv.RecentVoteCount, 0) AS RecentVoteCount,
    mpt.TagName AS MostFrequentTag,
    ucp.ClosedPostCount,
    ucp.LastClosedPost,
    CASE
        WHEN tau.PostCount > 100 AND COALESCE(urv.NetRecentVotes, 0) > 500 THEN 'Power User'
        WHEN ub.GoldBadges > 5 THEN 'Decorated'
        ELSE 'Active'
    END AS UserCategory,
    CASE
        WHEN tau.DisplayName ILIKE '%sql%' THEN 'Likely SQL Enthusiast'
        ELSE NULL
    END AS SpecialFlag,
    LENGTH(COALESCE(tau.DisplayName,'')) + COALESCE(ub.SilverBadges,0) AS DisplayNameScore
FROM
    TopActiveUsers tau
    LEFT JOIN UserBadges ub ON tau.UserId = ub.UserId
    LEFT JOIN UserRecentVotes urv ON tau.UserId = urv.UserId
    LEFT JOIN MostPopularTag mpt ON tau.UserId = mpt.UserId
    LEFT JOIN UserClosedPosts ucp ON tau.UserId = ucp.UserId
WHERE
    (ub.FirstBadgeDate IS NULL OR ub.LastBadgeDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 year')
    AND (ucp.ClosedPostCount IS NULL OR ucp.ClosedPostCount < tau.PostCount / 2)
    AND (mpt.TagName IS NULL OR LENGTH(mpt.TagName) <= 20)
ORDER BY
    -- complicated ordering for benchmarking
    tau.UserRank ASC,
    COALESCE(ub.GoldBadges,0) DESC,
    COALESCE(urv.NetRecentVotes,0) DESC,
    tau.DisplayName,
    Random()
LIMIT 100;