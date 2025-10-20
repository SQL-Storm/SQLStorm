-- {"query": "48069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 609} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as rn
    FROM Posts p
    WHERE p.CreationDate >= DATE('now', '-1 year')
),
UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId <> -1
    GROUP BY OwnerUserId
),
TopUsers AS (
    SELECT
        UserId,
        Reputation,
        (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 3) AS BronzeBadges
    FROM Users u
    ORDER BY Reputation DESC
    LIMIT 100
)
SELECT
    rp1.PostId AS LatestQuestionId,
    rp1.Score AS LatestQuestionScore,
    rp1.ViewCount AS LatestQuestionViewCount,
    rp1.AnswerCount AS LatestQuestionAnswerCount,
    rp1.CommentCount AS LatestQuestionCommentCount,
    rp2.PostId AS LatestAnswerId,
    rp2.Score AS LatestAnswerScore,
    rp2.CommentCount AS LatestAnswerCommentCount,
    tu.UserId AS TopUserId,
    tu.Reputation AS TopUserReputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    upc.TotalPosts AS TopUserTotalPosts,
    upc.QuestionCount AS TopUserQuestionCount,
    upc.AnswerCount AS TopUserAnswerCount
FROM RankedPosts rp1
JOIN Posts rp2 ON rp1.Id = rp2.ParentId AND rp2.PostTypeId = 2
JOIN TopUsers tu ON rp1.OwnerUserId = tu.UserId
JOIN UserPostCounts upc ON tu.UserId = upc.OwnerUserId
WHERE rp1.PostTypeId = 1 AND rp1.rn <= 10
ORDER BY rp1.CreationDate DESC, rp2.CreationDate DESC
LIMIT 50;