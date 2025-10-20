-- {"query": "35077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 872} 
WITH HighlyActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        DENSE_RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS ActivityRank
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.CreationDate < NOW() - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 200
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserVotes AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(v.Id) AS TotalVotesReceived
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
RecentEditStats AS (
    SELECT
        ph.UserId,
        COUNT(*) AS RecentEdits
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
      AND ph.CreationDate > NOW() - INTERVAL '90 days'
      AND ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
TagContributions AS (
    SELECT
        p.OwnerUserId AS UserId,
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
        COUNT(*) AS TagPostCount
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
),
TopTags AS (
    SELECT
        UserId,
        TagName,
        RANK() OVER (PARTITION BY UserId ORDER BY TagPostCount DESC) AS TagRank,
        TagPostCount
    FROM TagContributions
)
SELECT
    hau.UserId,
    hau.DisplayName,
    hau.ActivityRank,
    hau.TotalPosts,
    hau.Questions,
    hau.Answers,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uv.UpVotesReceived, 0) AS UpVotesReceived,
    COALESCE(uv.DownVotesReceived, 0) AS DownVotesReceived,
    COALESCE(uv.TotalVotesReceived, 0) AS TotalVotesReceived,
    COALESCE(res.RecentEdits, 0) AS EditsLast90d,
    tt.TagName AS TopTag1,
    tt.TagPostCount AS TopTag1PostCount
FROM HighlyActiveUsers hau
LEFT JOIN UserBadges ub ON hau.UserId = ub.UserId
LEFT JOIN UserVotes uv ON hau.UserId = uv.UserId
LEFT JOIN RecentEditStats res ON hau.UserId = res.UserId
LEFT JOIN (
    SELECT UserId, TagName, TagPostCount
    FROM TopTags
    WHERE TagRank = 1
) tt ON hau.UserId = tt.UserId
ORDER BY hau.ActivityRank ASC, hau.UserId
LIMIT 100;