-- {"query": "15091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 214820, "output_tokens": 63355} 
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        COUNT(b.Id) AS GoldBadgeCount,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS ExclusiveGoldBadges,
        DENSE_RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
), PostQualityAnalysis AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COALESCE(v.UpvoteCount, 0) AS UpvoteCount,
        COALESCE(v.DownvoteCount, 0) AS DownvoteCount,
        (v.UpvoteCount - v.DownvoteCount) / NULLIF(v.UpvoteCount + v.DownvoteCount, 0)::float AS VoteRatio
    FROM Posts p
    LEFT JOIN (
        SELECT 
            PostId, 
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
        FROM Votes
        GROUP BY PostId
    ) v ON p.Id = v.PostId
)
SELECT 
    ubc.UserId,
    ubc.DisplayName,
    ubc.GoldBadgeCount,
    ubc.ExclusiveGoldBadges,
    ubc.BadgeRank,
    AVG(pqa.Score) AS AvgPostScore,
    MAX(pqa.ViewCount) AS MaxViewCount,
    SUM(CASE WHEN pqa.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN pqa.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pqa.VoteRatio) AS MedianVoteRatio
FROM UserBadgeCounts ubc
JOIN Posts p ON ubc.UserId = p.OwnerUserId
JOIN PostQualityAnalysis pqa ON p.Id = pqa.Id
WHERE 
    pqa.VoteRatio IS NOT NULL 
    AND ubc.GoldBadgeCount > 5
    AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%')
GROUP BY 
    ubc.UserId, 
    ubc.DisplayName, 
    ubc.GoldBadgeCount, 
    ubc.ExclusiveGoldBadges, 
    ubc.BadgeRank
HAVING 
    AVG(pqa.Score) > 5
    AND SUM(CASE WHEN pqa.PostTypeId = 2 THEN 1 ELSE 0 END) > 10
ORDER BY 
    AvgPostScore DESC, 
    GoldBadgeCount DESC
LIMIT 100;