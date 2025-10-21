-- {"query": "55025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1297} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)          AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)          AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1)         AS QuestionScore,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2)         AS AnswerScore,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2)          AS UpVotesGiven,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3)          AS DownVotesGiven
    FROM Users u
    LEFT JOIN Posts  p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes  v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*)                                             AS TotalBadges,
        COUNT(*) FILTER (WHERE b.Class = 1)                 AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2)                 AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3)                 AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END)    AS TagBasedBadges
    FROM Badges b
    GROUP BY b.UserId
),
TopPosts AS (
    SELECT 
        p.OwnerUserId,
        p.Id,
        p.Title,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId 
                           ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.QuestionScore,
    us.AnswerScore,
    us.UpVotesGiven,
    us.DownVotesGiven,
    bs.TotalBadges,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.TagBasedBadges,
    tp.Id   AS TopQuestionId,
    tp.Title AS TopQuestionTitle,
    tp.Score AS TopQuestionScore
FROM UserStats us
LEFT JOIN BadgeStats bs ON bs.UserId = us.Id
LEFT JOIN TopPosts tp   ON tp.OwnerUserId = us.Id AND tp.rn = 1
WHERE us.Reputation > 10000
ORDER BY us.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
