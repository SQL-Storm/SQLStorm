-- {"query": "15080.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 189135, "output_tokens": 55677} 
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(CASE WHEN b.Class = 1 THEN b.Name END) AS GoldBadge,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
),
QuestionActivityStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id) AS AnswerCount,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Tags
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.BadgeCount,
    ubs.GoldBadge,
    ubs.AvgQuestionScore,
    qas.QuestionId,
    qas.Title,
    qas.Tags,
    qas.VoteCount,
    qas.CommentCount,
    qas.AnswerCount,
    COALESCE(qas.ScoreRank, 999) AS QuestionScoreRank,
    CASE 
        WHEN qas.AnswerCount > 5 THEN 'High Activity'
        WHEN qas.AnswerCount BETWEEN 1 AND 5 THEN 'Medium Activity'
        ELSE 'Low Activity'
    END AS QuestionActivityLevel,
    ROUND(
        (ubs.BadgeCount * 0.5) + 
        (qas.VoteCount * 0.3) + 
        (qas.CommentCount * 0.2),
        2
    ) AS ActivityScore
FROM UserBadgeStats ubs
FULL OUTER JOIN QuestionActivityStats qas 
    ON ubs.UserId = (
        SELECT OwnerUserId 
        FROM Posts 
        WHERE Id = qas.QuestionId
    )
WHERE 
    ubs.BadgeCount > 10 
    AND qas.VoteCount > 0
    AND (
        qas.Tags LIKE '%sql%' 
        OR qas.Tags LIKE '%database%'
    )
ORDER BY ActivityScore DESC
LIMIT 100;