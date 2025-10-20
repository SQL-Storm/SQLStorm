WITH UserActivityMetrics AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsPosted,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersPosted,
        SUM(CASE WHEN p.PostTypeId IN (1, 2) THEN COALESCE(p.Score,0) ELSE 0 END) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT c.Id) AS TotalComments,
        ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN p.PostTypeId IN (1, 2) THEN COALESCE(p.Score,0) ELSE 0 END) DESC) AS RankByScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(COALESCE(p.Score,0)) AS AvgScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    ORDER BY PostCount DESC
    FETCH FIRST 10 ROWS ONLY
),
UserTopTags AS (
    SELECT 
        p.OwnerUserId,
        t.TagName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Posts p
    JOIN Tags t ON p.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId, t.TagName
)
SELECT 
    uam.UserId,
    u.DisplayName,
    uam.QuestionsPosted,
    uam.AnswersPosted,
    uam.TotalScore,
    uam.LastPostDate,
    uam.GoldBadges,
    uam.SilverBadges,
    uam.BronzeBadges,
    uam.TotalComments,
    utt.TagName AS TopContributedTag
FROM UserActivityMetrics uam
JOIN Users u ON uam.UserId = u.Id
LEFT JOIN UserTopTags utt ON uam.UserId = utt.OwnerUserId AND utt.TagRank = 1
WHERE uam.RankByScore <= 100
ORDER BY uam.TotalScore DESC;