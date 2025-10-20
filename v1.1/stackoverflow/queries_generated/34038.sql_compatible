WITH RECURSIVE RecursiveUserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        b.Class,
        COUNT(b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, b.Class

    UNION ALL

    SELECT 
        r.UserId,
        r.DisplayName,
        r.Class,
        r.BadgeCount
    FROM RecursiveUserBadgeCounts r
    WHERE r.BadgeCount > 0
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT ph.Id) AS EditCount,
        (SELECT string_agg(tag, ', ') FROM (
             SELECT tag
             FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag
             ORDER BY tag
             LIMIT 3
         ) t) AS TopTags
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6)
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.Tags
    ORDER BY p.Score DESC, p.ViewCount DESC
    LIMIT 100
),
AnswerStats AS (
    SELECT 
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN a.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END) AS AnswersWithOwner
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
UserReputationStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        MAX(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS MaxAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING u.Reputation > 1000
    ORDER BY u.Reputation DESC
    LIMIT 50
)
SELECT
    q.Id AS QuestionId,
    q.Title,
    q.OwnerUserId,
    u.DisplayName AS OwnerName,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.CommentCount,
    q.EditCount,
    q.TopTags,
    a.TotalAnswers,
    a.AvgAnswerScore,
    a.MaxAnswerScore,
    a.AnswersWithOwner,
    urs.Reputation AS OwnerReputation,
    urs.QuestionCount AS OwnerQuestionCount,
    urs.AnswerCount AS OwnerAnswerCount,
    urs.MaxAnswerScore AS OwnerMaxAnswerScore,
    urs.AvgAnswerScore AS OwnerAvgAnswerScore,
    urs.GoldBadges,
    urs.SilverBadges,
    urs.BronzeBadges
FROM TopQuestions q
LEFT JOIN AnswerStats a ON q.Id = a.QuestionId
LEFT JOIN Users u ON q.OwnerUserId = u.Id
LEFT JOIN UserReputationStats urs ON q.OwnerUserId = urs.Id
WHERE q.AnswerCount > 0
ORDER BY q.Score DESC, q.ViewCount DESC
LIMIT 20;