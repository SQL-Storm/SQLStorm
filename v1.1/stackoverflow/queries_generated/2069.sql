-- {"query": "2069.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 522} 

WITH UserBadges AS (
    SELECT 
        u.Id AS UserId, 
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
TopUsers AS (
    SELECT 
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, 
        ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS Rank
    FROM Users u
    JOIN UserBadges ub ON u.Id = ub.UserId
),
RecentQuestions AS (
    SELECT 
        p.Id AS PostId, p.Title, p.Score, p.ViewCount, p.CreationDate, 
        p.OwnerUserId, p.Tags, COUNT(a.Id) AS AnswerCount
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, 
             p.OwnerUserId, p.Tags
    HAVING COUNT(a.Id) > 5
),
HighActivityQuestions AS (
    SELECT 
        rq.PostId, rq.Title, rq.OwnerUserId AS QuestionOwner, 
        COUNT(c.Id) AS CommentCount
    FROM RecentQuestions rq
    LEFT JOIN Comments c ON rq.PostId = c.PostId
    WHERE rq.ViewCount > 1000
    GROUP BY rq.PostId, rq.Title, rq.OwnerUserId
    HAVING COUNT(c.Id) > 3
),
FinalResult AS (
    SELECT 
        tu.DisplayName, tu.Reputation, tu.GoldBadges, tu.SilverBadges, tu.BronzeBadges, 
        ha.Title AS QuestionTitle, ha.CommentCount
    FROM TopUsers tu
    INNER JOIN HighActivityQuestions ha ON tu.Id = ha.QuestionOwner
    WHERE tu.Rank <= 50
)
SELECT * FROM FinalResult;
