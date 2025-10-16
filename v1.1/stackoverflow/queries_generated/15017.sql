-- {"query": "15017.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 42030, "output_tokens": 12444} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.ViewCount) AS AvgPostViews,
        MAX(p.LastActivityDate) AS LastActivePostDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVoteCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagPopularity AS (
    SELECT 
        unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName,
        COUNT(*) AS TagFrequency,
        AVG(Score) AS AvgTagScore,
        MAX(ViewCount) AS MaxTagViews
    FROM Posts
    WHERE Tags IS NOT NULL AND PostTypeId = 1
    GROUP BY TagName
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.PostCount,
    ups.TotalPostScore,
    ups.AvgPostViews,
    tp.TagName,
    tp.TagFrequency,
    tp.AvgTagScore,
    RANK() OVER (PARTITION BY tp.TagName ORDER BY ups.Reputation DESC) AS UserTagRank,
    CASE 
        WHEN ups.Reputation > 10000 THEN 'High Rep'
        WHEN ups.Reputation > 1000 THEN 'Medium Rep'
        ELSE 'Low Rep'
    END AS RepCategory,
    COALESCE(tp.MaxTagViews, 0) * 
    (CASE 
        WHEN ups.Reputation > 10000 THEN 1.5
        WHEN ups.Reputation > 1000 THEN 1.2
        ELSE 1.0
    END) AS WeightedTagViews
FROM UserPostStats ups
CROSS JOIN TagPopularity tp
WHERE 
    ups.PostCount > 5 
    AND tp.TagFrequency > 10
    AND (ups.Reputation * ups.PostCount) > 5000
ORDER BY WeightedTagViews DESC, UserTagRank
LIMIT 100;