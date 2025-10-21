WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT p.Id) AS QuestionsWithTag,
        AVG(p.Score) AS AvgQuestionScore,
        AVG(p.AnswerCount) AS AvgAnswersPerQuestion,
        SUM(p.ViewCount) AS TotalTagViews,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
        AND t.Count > 1000
    GROUP BY t.TagName, t.Count
),
PostEngagement AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate,
        EXTRACT(EPOCH FROM (MAX(ph.CreationDate) - p.CreationDate)) / 3600 AS HoursToLastEdit,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
        COUNT(DISTINCT pl.Id) AS LinkedPostCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '6 months'
        AND p.Score > 0
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount
),
UserActivity AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) AS ActivityMonth,
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS MonthlyPosts,
        COUNT(DISTINCT c.Id) AS MonthlyComments,
        COUNT(DISTINCT v.Id) AS MonthlyVotes,
        SUM(p.Score) AS MonthlyScoreGained,
        AVG(p.Score) AS AvgMonthlyScore,
        DENSE_RANK() OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) 
                          ORDER BY COUNT(DISTINCT p.Id) DESC) AS MonthlyRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId 
        AND DATE_TRUNC('month', c.CreationDate) = DATE_TRUNC('month', p.CreationDate)
    LEFT JOIN Votes v ON u.Id = v.UserId 
        AND DATE_TRUNC('month', v.CreationDate) = DATE_TRUNC('month', p.CreationDate)
    WHERE p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
    GROUP BY DATE_TRUNC('month', p.CreationDate), u.Id
)
SELECT 
    um.DisplayName,
    um.Reputation,
    um.TotalPosts,
    um.Questions,
    um.Answers,
    ROUND(um.AvgPostScore, 2) AS AvgPostScore,
    um.TotalViews,
    um.GoldBadges,
    um.SilverBadges,
    um.BronzeBadges,
    tt.TagName AS TopTag,
    tt.AvgQuestionScore AS TagAvgScore,
    pe.Title AS TopPost,
    pe.Score AS TopPostScore,
    pe.ViewCount AS TopPostViews,
    pe.CommentCount AS TopPostComments,
    pe.UpVotes - pe.DownVotes AS TopPostNetVotes,
    ua.ActivityMonth AS MostActiveMonth,
    ua.MonthlyPosts AS PostsInMostActiveMonth,
    ua.AvgMonthlyScore AS AvgScoreInMostActiveMonth,
    ROW_NUMBER() OVER (ORDER BY um.Reputation DESC, um.TotalPosts DESC) AS OverallRank
FROM UserMetrics um
CROSS JOIN LATERAL (
    SELECT tt.*
    FROM TopTags tt
    JOIN Posts p ON p.Tags LIKE '%' || '<' || tt.TagName || '>' || '%'
    WHERE p.OwnerUserId = um.Id
    ORDER BY tt.TagUsageCount DESC
    LIMIT 1
) tt
CROSS JOIN LATERAL (
    SELECT pe.*
    FROM PostEngagement pe
    JOIN Posts p ON pe.PostId = p.Id
    WHERE p.OwnerUserId = um.Id
    ORDER BY pe.Score DESC, pe.ViewCount DESC
    LIMIT 1
) pe
CROSS JOIN LATERAL (
    SELECT ua.*
    FROM UserActivity ua
    WHERE ua.UserId = um.Id
    ORDER BY ua.MonthlyPosts DESC, ua.AvgMonthlyScore DESC
    LIMIT 1
) ua
WHERE um.Reputation > 5000
ORDER BY um.Reputation DESC, um.TotalPosts DESC
LIMIT 100;