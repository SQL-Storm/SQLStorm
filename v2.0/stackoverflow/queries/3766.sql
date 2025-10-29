WITH 
RecentPosts AS (
    SELECT 
        p.OwnerUserId AS UserId,
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
TopRecent AS (
    SELECT *
    FROM RecentPosts
    WHERE rn <= 5
),
BadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
TagStats AS (
    SELECT 
        u.Id AS UserId,
        t.TagName,
        COUNT(*) AS TagQuestionCount,
        AVG(p.Score) AS AvgTagScore,
        MAX(p.CreationDate) AS LastTagUse
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTR(p.Tags,2,LENGTH(p.Tags)-2), '><')) AS Tag
    ) AS taglist(tag) ON TRUE
    JOIN Tags t ON t.TagName = taglist.tag
    GROUP BY u.Id, t.TagName
),
PostVoteSummary AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(CASE WHEN vt.Id NOT IN (2,3) THEN 1 END) AS OtherVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
NoPostUsers AS (
    SELECT u.Id
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.Id IS NULL
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(bc.GoldBadges,0) AS GoldBadges,
    COALESCE(bc.SilverBadges,0) AS SilverBadges,
    COALESCE(bc.BronzeBadges,0) AS BronzeBadges,
    COALESCE(bc.TotalBadges,0) AS TotalBadges,
    rp.PostId,
    rp.PostTypeId,
    rp.Title,
    rp.Score AS PostScore,
    rp.CreationDate AS PostDate,
    COALESCE(pvs.UpVotes,0) AS PostUpVotes,
    COALESCE(pvs.DownVotes,0) AS PostDownVotes,
    COALESCE(pvs.OtherVotes,0) AS PostOtherVotes,
    ts.TagName,
    ts.TagQuestionCount,
    ROUND(CAST(ts.AvgTagScore AS DECIMAL),2) AS AvgTagScore,
    ts.LastTagUse,
    CASE 
        WHEN u.Location IS NULL THEN 'Location unknown'
        ELSE u.Location
    END AS UserLocation,
    CASE 
        WHEN u.WebsiteUrl LIKE '%.edu%' THEN 'Academic'
        WHEN u.WebsiteUrl LIKE '%.org%' THEN 'Non-profit'
        ELSE 'Other'
    END AS WebsiteCategory,
    EXISTS (
        SELECT 1 
        FROM Comments c 
        WHERE c.UserId = u.Id AND c.Score < 0
    ) AS HasNegativeComments,
    rp.rn
FROM Users u
LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
LEFT JOIN TopRecent rp ON rp.UserId = u.Id
LEFT JOIN PostVoteSummary pvs ON pvs.PostId = rp.PostId
LEFT JOIN TagStats ts ON ts.UserId = u.Id
WHERE 
    (u.Reputation > 10000 OR COALESCE(bc.TotalBadges,0) > 5)
    AND (rp.rn IS NOT NULL OR u.Id IN (SELECT Id FROM NoPostUsers))
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    bc.TotalBadges,
    rp.PostId,
    rp.PostTypeId,
    rp.Title,
    rp.Score,
    rp.CreationDate,
    pvs.UpVotes,
    pvs.DownVotes,
    pvs.OtherVotes,
    ts.TagName,
    ts.TagQuestionCount,
    ts.AvgTagScore,
    ts.LastTagUse,
    u.Location,
    u.WebsiteUrl,
    rp.rn
ORDER BY 
    u.Reputation DESC,
    bc.TotalBadges DESC,
    rp.CreationDate NULLS LAST;