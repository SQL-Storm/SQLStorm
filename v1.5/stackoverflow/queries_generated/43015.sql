-- {"query": "43015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 661} 

WITH UserBadges AS (
    SELECT u.Id AS UserId, COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
), HighReputationUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, ub.BadgeCount
    FROM Users u
    JOIN UserBadges ub ON u.Id = ub.UserId
    WHERE u.Reputation > 10000
), UserPosts AS (
    SELECT 
        p.OwnerUserId, 
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.OwnerUserId
), TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.Score > 50
    ORDER BY p.Score DESC
    LIMIT 100
), CommentsSummary AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
)
SELECT 
    hru.DisplayName,
    hru.Reputation,
    hru.BadgeCount,
    COALESCE(up.QuestionCount, 0) AS QuestionCount,
    COALESCE(up.AnswerCount, 0) AS AnswerCount,
    COALESCE(up.AvgQuestionScore, 0) AS AvgQuestionScore,
    COALESCE(up.AvgAnswerScore, 0) AS AvgAnswerScore,
    tq.PostId,
    tq.Title,
    tq.Score AS QuestionScore,
    tq.ViewCount,
    cs.CommentCount,
    cs.LastCommentDate
FROM HighReputationUsers hru
LEFT JOIN UserPosts up ON hru.Id = up.OwnerUserId
LEFT JOIN TopQuestions tq ON hru.Id = tq.OwnerUserId
LEFT JOIN CommentsSummary cs ON tq.PostId = cs.PostId
ORDER BY hru.Reputation DESC, tq.Score DESC;
