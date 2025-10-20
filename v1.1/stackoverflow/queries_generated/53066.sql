-- {"query": "53066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 616} 
WITH TopTags AS (
    SELECT TagName, Count
    FROM Tags
    ORDER BY Count DESC
    LIMIT 10
),
UserPosts AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)  -- Questions and Answers
    GROUP BY p.OwnerUserId
    HAVING COUNT(p.Id) > 100
),
UserBadges AS (
    SELECT 
        UserId,
        COUNT(Id) AS BadgeCount,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM Badges
    GROUP BY UserId
),
UserVotes AS (
    SELECT 
        v.UserId,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
PostTagUsage AS (
    SELECT 
        p.OwnerUserId AS UserId,
        t.TagName,
        COUNT(p.Id) AS PostsInTag
    FROM Posts p
    CROSS JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS tag_array
    JOIN TopTags t ON tag_array = t.TagName
    WHERE p.PostTypeId = 1  -- Questions
    GROUP BY p.OwnerUserId, t.TagName
),
RankedUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        up.PostCount,
        up.AvgScore,
        up.TotalViews,
        ub.BadgeCount,
        ub.GoldBadges,
        uv.VoteCount,
        uv.UpVotesGiven,
        ROW_NUMBER() OVER (PARTITION BY ptu.TagName ORDER BY ptu.PostsInTag DESC) AS RankInTag
    FROM Users u
    JOIN UserPosts up ON u.Id = up.UserId
    JOIN UserBadges ub ON u.Id = ub.UserId
    JOIN UserVotes uv ON u.Id = uv.UserId
    JOIN PostTagUsage ptu ON u.Id = ptu.UserId
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.PostCount,
    ru.AvgScore,
    ru.TotalViews,
    ru.BadgeCount,
    ru.GoldBadges,
    ru.VoteCount,
    ru.UpVotesGiven,
    ptu.TagName,
    ru.RankInTag
FROM RankedUsers ru
JOIN PostTagUsage ptu ON ru.UserId = ptu.UserId
WHERE ru.RankInTag <= 5
ORDER BY ptu.TagName, ru.RankInTag;