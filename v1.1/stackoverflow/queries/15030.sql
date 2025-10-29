-- {"query": "15030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 949}
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        DENSE_RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostActivityAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        v.UpvoteCount,
        v.DownvoteCount,
        COALESCE(c.CommentCount, 0) AS PostCommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostSequence
    FROM Posts p
    LEFT JOIN (
        SELECT 
            PostId, 
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
        FROM Votes
        GROUP BY PostId
    ) v ON p.Id = v.PostId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount 
        FROM Comments 
        GROUP BY PostId
    ) c ON p.Id = c.PostId
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ROUND(AVG(pa.Score), 2) AS AveragePostScore,
    SUM(pa.UpvoteCount) AS TotalUpvotes,
    SUM(pa.DownvoteCount) AS TotalDownvotes,
    MAX(pa.PostCommentCount) AS MaxCommentsOnAPost,
    COUNT(DISTINCT CASE WHEN pa.PostTypeId = 1 THEN pa.PostId END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN pa.PostTypeId = 2 THEN pa.PostId END) AS AnswerCount,
    CASE 
        WHEN AVG(pa.Score) > 5 THEN 'High Impact'
        WHEN AVG(pa.Score) BETWEEN 1 AND 5 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS UserContributionTier
FROM UserBadgeStats ubs
JOIN PostActivityAnalysis pa ON ubs.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pa.PostId)
WHERE ubs.TotalBadges > 0
GROUP BY 
    ubs.UserId, 
    ubs.DisplayName, 
    ubs.TotalBadges, 
    ubs.GoldBadges, 
    ubs.SilverBadges, 
    ubs.BronzeBadges
HAVING 
    SUM(pa.UpvoteCount) > 10 
    AND COUNT(DISTINCT pa.PostId) > 5
ORDER BY TotalBadges DESC, AveragePostScore DESC
LIMIT 100;
