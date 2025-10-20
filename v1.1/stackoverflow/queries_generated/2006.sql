-- {"query": "2006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 549} 

WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(p.Id) AS PostCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        RANK() OVER (ORDER BY p.Score DESC) AS RankByScore
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
),
BadgeCount AS (
    SELECT 
        b.UserId, 
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
PostStats AS (
    SELECT
        a.UserId,
        q.PostId,
        q.Title,
        q.Score,
        q.AnswerCount,
        a.DisplayName,
        a.Reputation,
        a.PostCount,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges
    FROM
        ActiveUsers a
    JOIN
        TopQuestions q ON q.PostId IN (
            SELECT PostId 
            FROM Posts 
            WHERE OwnerUserId = a.UserId
        ) AND q.RankByScore <= 10
    LEFT JOIN
        BadgeCount bc ON a.UserId = bc.UserId
)
SELECT 
    ps.UserId,
    ps.DisplayName,
    ROUND((ps.GoldBadges * 3 + ps.SilverBadges * 2 + ps.BronzeBadges) / NULLIF(ps.PostCount, 0), 2) AS BadgeScoreRate,
    COALESCE(ps.GoldBadges, 0) AS TotalGoldBadges,
    ps.Title,
    ps.Score,
    ps.AnswerCount
FROM 
    PostStats ps
WHERE 
    ps.Reputation > 5000
ORDER BY 
    BadgeScoreRate DESC, ps.Score DESC, ps.Title ASC;
