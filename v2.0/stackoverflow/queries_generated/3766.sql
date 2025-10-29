-- {"query": "3766.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1334} 
WITH 
-- Recent five posts per user (questions or answers)
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
-- Badge aggregation per user
BadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
-- Tag activity (questions that contain each tag)
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
        SELECT UNNEST(string_to_array(substr(p.Tags,2,length(p.Tags)-2), '><')) AS Tag
    ) AS taglist(tag)
    JOIN Tags t ON t.TagName = taglist.tag
    GROUP BY u.Id, t.TagName
),
-- Vote summary per post (including possible NULLs)
PostVoteSummary AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(*) FILTER (WHERE vt.Id NOT IN (2,3)) AS OtherVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
-- Users with no posts (to test outer join behavior)
NoPostUsers AS (
    SELECT u.Id
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.Id IS NULL
)
-- Final result combining everything
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
    ROUND(ts.AvgTagScore::numeric,2) AS AvgTagScore,
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
    ) AS HasNegativeComments
FROM Users u
LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
LEFT JOIN TopRecent rp ON rp.UserId = u.Id
LEFT JOIN PostVoteSummary pvs ON pvs.PostId = rp.PostId
LEFT JOIN TagStats ts ON ts.UserId = u.Id
WHERE 
    (u.Reputation > 10000 OR bc.TotalBadges > 5)
    AND (rp.rn IS NOT NULL OR u.Id IN (SELECT Id FROM NoPostUsers))
ORDER BY 
    u.Reputation DESC,
    bc.TotalBadges DESC,
    rp.CreationDate NULLS LAST;