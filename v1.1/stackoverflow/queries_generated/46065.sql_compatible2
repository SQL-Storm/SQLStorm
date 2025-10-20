WITH TopQuestionUsers AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT p.Id) >= 10
),
TagPerformance AS (
    SELECT 
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName,
        p.Id AS PostId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '18 months'
),
UserBadgeMetrics AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS TagBasedBadges
    FROM Badges b
    WHERE b.Date >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
    GROUP BY b.UserId
),
AnswerEngagement AS (
    SELECT 
        a.OwnerUserId,
        a.ParentId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted,
        COUNT(DISTINCT c.Id) AS CommentCount,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600 AS HoursToAnswer,
        a.Id
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Comments c ON a.Id = c.PostId
    WHERE a.PostTypeId = 2
      AND a.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '18 months'
      AND a.OwnerUserId IS NOT NULL
    GROUP BY a.Id, a.OwnerUserId, a.ParentId, a.Score, a.CreationDate, q.Score, q.ViewCount, q.AcceptedAnswerId, q.CreationDate
),
VotePatterns AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS Favorites,
        MIN(v.CreationDate) AS FirstVoteDate,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '18 months'
    GROUP BY v.PostId
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    tqu.QuestionCount,
    tqu.AvgScore AS AvgQuestionScore,
    tqu.TotalViews,
    ubm.GoldBadges,
    ubm.SilverBadges,
    ubm.BronzeBadges,
    ubm.TagBasedBadges,
    tp.TagName AS MostUsedTag,
    COUNT(DISTINCT ae.ParentId) AS QuestionsAnswered,
    AVG(ae.AnswerScore) AS AvgAnswerScore,
    SUM(ae.IsAccepted) AS AcceptedAnswers,
    AVG(ae.HoursToAnswer) AS AvgHoursToAnswer,
    AVG(ae.CommentCount) AS AvgCommentsPerAnswer,
    AVG(vp.UpVotes) AS AvgUpVotesPerPost,
    AVG(vp.DownVotes) AS AvgDownVotesPerPost,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tp.Score) AS MedianPostScore,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY tp.ViewCount) AS P75ViewCount,
    COUNT(DISTINCT CASE WHEN tp.AnswerCount >= 5 THEN tp.PostId END) AS HighlyAnsweredQuestions,
    STDDEV(tp.Score) AS ScoreStdDev,
    MAX(tp.Score) AS BestPostScore,
    SUM(CASE WHEN vp.Favorites > 10 THEN 1 ELSE 0 END) AS HighlyFavoritedPosts
FROM Users u
INNER JOIN TopQuestionUsers tqu ON u.Id = tqu.OwnerUserId
LEFT JOIN UserBadgeMetrics ubm ON u.Id = ubm.UserId
LEFT JOIN TagPerformance tp ON u.Id = tp.OwnerUserId
LEFT JOIN AnswerEngagement ae ON u.Id = ae.OwnerUserId
LEFT JOIN VotePatterns vp ON tp.PostId = vp.PostId
WHERE u.Reputation > 1000
  AND u.CreationDate <= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, tqu.QuestionCount, 
         tqu.AvgScore, tqu.TotalViews, ubm.GoldBadges, ubm.SilverBadges, 
         ubm.BronzeBadges, ubm.TagBasedBadges, tp.TagName
HAVING COUNT(DISTINCT tp.PostId) >= 15
ORDER BY (COALESCE(ubm.GoldBadges,0) * 3 + COALESCE(ubm.SilverBadges,0) * 2 + COALESCE(ubm.BronzeBadges,0)) DESC,
         u.Reputation DESC
LIMIT 100;