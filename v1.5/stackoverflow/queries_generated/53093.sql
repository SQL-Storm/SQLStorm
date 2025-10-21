-- {"query": "53093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 975} 

WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)  -- Questions and Answers
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserVotes AS (
    SELECT 
        v.UserId,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY v.UserId
),
TopTags AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagUsage,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 1000
),
UserTagActivity AS (
    SELECT 
        p.OwnerUserId AS UserId,
        tt.TagId,
        COUNT(p.Id) AS PostsInTag,
        SUM(p.Score) AS ScoreInTag
    FROM Posts p
    CROSS JOIN LATERAL STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') AS tag_array
    INNER JOIN TopTags tt ON tt.TagName = ANY(tag_array)
    WHERE p.PostTypeId = 1  -- Questions
    GROUP BY p.OwnerUserId, tt.TagId
    HAVING COUNT(p.Id) > 5
),
AggregatedData AS (
    SELECT 
        au.UserId,
        au.Reputation,
        au.PostCount,
        au.TotalScore,
        au.LastPostDate,
        ub.BadgeCount,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        uv.VoteCount,
        uv.UpVotesGiven,
        uv.DownVotesGiven,
        STRING_AGG(CONCAT(tt.TagName, ': ', uta.PostsInTag, ' posts, ', uta.ScoreInTag, ' score'), '; ') AS TagActivities
    FROM ActiveUsers au
    LEFT JOIN UserBadges ub ON au.UserId = ub.UserId
    LEFT JOIN UserVotes uv ON au.UserId = uv.UserId
    LEFT JOIN UserTagActivity uta ON au.UserId = uta.UserId
    LEFT JOIN TopTags tt ON uta.TagId = tt.TagId
    WHERE tt.TagRank <= 10
    GROUP BY 
        au.UserId, au.Reputation, au.PostCount, au.TotalScore, au.LastPostDate,
        ub.BadgeCount, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
        uv.VoteCount, uv.UpVotesGiven, uv.DownVotesGiven
)
SELECT 
    u.DisplayName,
    ad.Reputation,
    ad.PostCount,
    ad.TotalScore,
    ad.LastPostDate,
    ad.BadgeCount,
    ad.GoldBadges,
    ad.SilverBadges,
    ad.BronzeBadges,
    ad.VoteCount,
    ad.UpVotesGiven,
    ad.DownVotesGiven,
    ad.TagActivities,
    (SELECT COUNT(c.Id) FROM Comments c WHERE c.UserId = u.Id) AS CommentCount,
    (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS EditCount,
    RANK() OVER (ORDER BY ad.Reputation DESC, ad.TotalScore DESC) AS OverallRank
FROM AggregatedData ad
INNER JOIN Users u ON ad.UserId = u.Id
WHERE ad.Reputation > 10000
ORDER BY OverallRank
LIMIT 100;
