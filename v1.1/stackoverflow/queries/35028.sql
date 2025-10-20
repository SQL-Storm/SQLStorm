WITH HighActivityUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(u.Reputation) OVER () AS AvgReputation
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10 AND COUNT(DISTINCT c.Id) > 10
),
UserTags AS (
    SELECT 
        p.OwnerUserId AS UserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId = 1
),
TopTags AS (
    SELECT ut.UserId, ut.Tag, ut.TagUsage FROM (
        SELECT 
            ut.UserId,
            ut.Tag,
            COUNT(*) AS TagUsage,
            ROW_NUMBER() OVER (PARTITION BY ut.UserId ORDER BY COUNT(*) DESC) AS rn
        FROM UserTags ut
        GROUP BY ut.UserId, ut.Tag
    ) ut
    WHERE ut.rn <= 3
),
ScoreGrowth AS (
    SELECT
        p.OwnerUserId AS UserId,
        DATE_TRUNC('month', p.CreationDate) AS Month,
        SUM(p.Score) AS MonthlyScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    GROUP BY p.OwnerUserId, DATE_TRUNC('month', p.CreationDate)
),
ScoreTrends AS (
    SELECT
        UserId,
        AVG(MonthlyScore) AS AvgMonthlyScore,
        MAX(MonthlyScore) AS PeakScore,
        MIN(MonthlyScore) AS MinScore,
        MAX(MonthlyScore) - MIN(MonthlyScore) AS ScoreVariance
    FROM ScoreGrowth
    GROUP BY UserId
)
SELECT 
    hau.UserId,
    hau.DisplayName,
    hau.PostCount,
    hau.CommentCount,
    hau.VoteCount,
    hau.BadgeCount,
    hau.AvgReputation,
    ARRAY_AGG(DISTINCT tt.Tag) AS TopTags,
    st.AvgMonthlyScore,
    st.PeakScore,
    st.MinScore,
    st.ScoreVariance,
    u.Location,
    u.WebsiteUrl,
    u.ProfileImageUrl
FROM HighActivityUsers hau
LEFT JOIN TopTags tt ON hau.UserId = tt.UserId
LEFT JOIN ScoreTrends st ON hau.UserId = st.UserId
LEFT JOIN Users u ON hau.UserId = u.Id
GROUP BY 
    hau.UserId, hau.DisplayName, hau.PostCount, hau.CommentCount, hau.VoteCount, 
    hau.BadgeCount, hau.AvgReputation, st.AvgMonthlyScore, st.PeakScore, st.MinScore, 
    st.ScoreVariance, u.Location, u.WebsiteUrl, u.ProfileImageUrl
ORDER BY st.ScoreVariance DESC NULLS LAST, hau.PostCount DESC
LIMIT 50;