-- {"query": "16004.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 11675, "output_tokens": 11073} 

WITH UserActivityMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        EXTRACT(YEAR FROM u.CreationDate) AS JoinYear,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) AS AvgQuestionViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2015-01-01'
        AND u.Reputation > 100
        AND (u.Location IS NULL OR u.Location NOT LIKE '%India%')
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5
),
BadgeRankings AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ') AS GoldBadgeNames,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM b.Date) ORDER BY COUNT(*) DESC) AS YearlyBadgeRank,
        DENSE_RANK() OVER (ORDER BY COUNT(*) FILTER (WHERE b.Class = 1) DESC NULLS LAST) AS GoldBadgeDenseRank
    FROM Badges b
    WHERE b.Date >= '2016-01-01'
    GROUP BY b.UserId, EXTRACT(YEAR FROM b.Date)
),
TopAnsweredQuestions AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId AS QuestionOwnerId,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerId,
        a.Score AS AnswerScore,
        COALESCE(a.CommentCount, 0) + COALESCE(q.CommentCount, 0) AS TotalComments,
        CASE 
            WHEN q.AcceptedAnswerId = a.Id THEN 'Accepted'
            WHEN a.Score >= 10 THEN 'Highly Rated'
            WHEN a.Score > 0 THEN 'Positive'
            WHEN a.Score = 0 THEN 'Neutral'
            ELSE 'Negative'
        END AS AnswerCategory,
        LAG(a.Score, 1, 0) OVER (PARTITION BY q.Id ORDER BY a.CreationDate) AS PreviousAnswerScore,
        LEAD(a.CreationDate, 1) OVER (PARTITION BY q.Id ORDER BY a.CreationDate) - a.CreationDate AS TimeToNextAnswer
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1
        AND a.PostTypeId = 2
        AND q.CreationDate BETWEEN '2017-01-01' AND '2020-12-31'
        AND q.AnswerCount >= 3
        AND q.Score > 5
),
VotePatterns AS (
    SELECT 
        v.PostId,
        v.UserId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvoteCount,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvoteCount,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS FavoriteCount,
        MAX(v.CreationDate) AS LastVoteDate,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY v.CreationDate) AS MedianVoteDate
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3, 5)
        AND v.CreationDate >= '2018-01-01'
    GROUP BY v.PostId, v.UserId
)
SELECT 
    uam.DisplayName,
    uam.Reputation,
    uam.JoinYear,
    uam.TotalPosts,
    uam.QuestionCount,
    uam.AnswerCount,
    ROUND(uam.TotalScore::numeric / NULLIF(uam.TotalPosts, 0), 2) AS AvgScorePerPost,
    COALESCE(br.GoldBadges, 0) AS GoldBadges,
    COALESCE(br.SilverBadges, 0) AS SilverBadges,
    COALESCE(br.BronzeBadges, 0) AS BronzeBadges,
    SUBSTRING(COALESCE(br.GoldBadgeNames, 'None'), 1, 100) AS TopGoldBadges,
    (SELECT COUNT(DISTINCT taq.QuestionId)
     FROM TopAnsweredQuestions taq
     WHERE taq.AnswerOwnerId = uam.Id
        AND taq.AnswerCategory IN ('Accepted', 'Highly Rated')) AS QualityAnswersCount,
    (SELECT AVG(vp.UpvoteCount::numeric / NULLIF(vp.UpvoteCount + vp.DownvoteCount, 0))
     FROM VotePatterns vp
     INNER JOIN Posts p ON vp.PostId = p.Id
     WHERE p.OwnerUserId = uam.Id) AS UpvoteRatio,
    CASE 
        WHEN uam.Reputation > 10000 AND COALESCE(br.GoldBadges, 0) > 5 THEN 'Elite'
        WHEN uam.Reputation > 5000 AND COALESCE(br.GoldBadges, 0) > 2 THEN 'Expert'
        WHEN uam.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserTier,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - uam.CreationDate)) / 86400 AS DaysSinceJoining,
    EXISTS (
        SELECT 1 
        FROM Posts p2
        WHERE p2.OwnerUserId = uam.Id
            AND p2.PostTypeId = 2
            AND p2.Id IN (SELECT AcceptedAnswerId FROM Posts WHERE AcceptedAnswerId IS NOT NULL)
    ) AS HasAcceptedAnswer,
    (SELECT STRING_AGG(DISTINCT t.TagName, '|' ORDER BY t.TagName)
     FROM Posts p3
     CROSS JOIN LATERAL string_to_array(substring(p3.Tags, 2, length(p3.Tags)-2), '><') AS tag_array(tag)
     INNER JOIN Tags t ON t.TagName = tag_array.tag
     WHERE p3.OwnerUserId = uam.Id
        AND p3.PostTypeId = 1
        AND t.Count > 1000
     LIMIT 10) AS PopularTagsUsed
FROM UserActivityMetrics uam
LEFT JOIN LATERAL (
    SELECT * FROM BadgeRankings br2
    WHERE br2.UserId = uam.Id
    ORDER BY br2.YearlyBadgeRank
    LIMIT 1
) br ON true
WHERE uam.TotalScore > 50
    AND (uam.AvgQuestionViews IS NULL OR uam.AvgQuestionViews > 100)
ORDER BY 
    CASE WHEN uam.Reputation > 10000 THEN 1 ELSE 2 END,
    uam.TotalScore DESC,
    COALESCE(br.GoldBadges, 0) DESC
LIMIT 500;
