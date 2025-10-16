-- {"query": "5036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1219} 
WITH RecentActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(b.BadgeCount, 0) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY u.LastAccessDate DESC) AS rn
    FROM Users u
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount
        FROM Badges
        WHERE Date > NOW() - INTERVAL '1 year'
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
)
, QuestionDetail AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.AnswerCount,
        string_agg(SUBSTRING(t, 1, 10), ',') AS TAGS,
        COUNT(DISTINCT c.Id) AS Commenters,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT regexp_split_to_table(substring(p.Tags, 2, length(p.Tags)-2), '><') AS t
    ) tag ON TRUE
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1 AND p.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY p.Id
)
, TopRecentQuestions AS (
    SELECT q.*, rau.DisplayName, rau.Reputation, rau.BadgeCount
    FROM QuestionDetail q
    LEFT JOIN RecentActiveUsers rau ON q.OwnerUserId = rau.UserId
    WHERE (rau.rn IS NULL OR rau.rn <= 100)
)
, AnswersAgg AS (
    SELECT 
        a.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.CreationDate) AS LatestAnswerDate,
        SUM(CASE WHEN au.Reputation > 10000 THEN 1 ELSE 0 END) AS HighRepAnswers
    FROM Posts a
    LEFT JOIN Users au ON a.OwnerUserId = au.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
)
SELECT
    q.PostId,
    q.Title,
    q.DisplayName AS QuestionOwner,
    q.Reputation AS OwnerReputation,
    q.BadgeCount AS OwnerRecentBadges,
    q.CreationDate AS QuestionDate,
    q.ViewCount,
    q.Score AS QuestionScore,
    COALESCE(a.AnswerCount, 0) AS AnswerCount,
    COALESCE(a.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(a.LatestAnswerDate, NULL) AS LatestAnswerDate,
    q.TAGs,
    q.Commenters,
    q.LastCommentDate,
    q.VoteCount,
    q.Upvotes,
    q.Downvotes,
    CASE 
        WHEN COALESCE(a.HighRepAnswers, 0) >= 2 THEN 'Popular among high-rep users'
        ELSE 'Normal'
    END AS PopularityTag,
    CASE 
        WHEN q.AnswerCount = 0
            AND q.VoteCount > 10
            AND q.Score < 0 THEN 'Hot but Unanswered & Downvoted'
        WHEN q.AnswerCount > 5
            AND q.Upvotes > 100 THEN 'Highly Active'
        WHEN q.Commenters > 10 THEN 'Much Discussed'
        ELSE 'Typical'
    END AS EngagementTag
FROM TopRecentQuestions q
LEFT JOIN AnswersAgg a ON a.QuestionId = q.PostId
WHERE 
    q.ViewCount > 50
    AND (q.DisplayName IS NOT NULL OR q.OwnerUserId IS NULL)
    AND (
        q.Score > 5 
        OR q.VoteCount > 10
        OR (q.Title ILIKE '%performance%' OR q.TAGs ILIKE '%benchmark%')
    )
ORDER BY
    COALESCE(a.HighRepAnswers,0) DESC,
    q.Score DESC,
    q.VoteCount DESC,
    q.LastCommentDate DESC
LIMIT 100
UNION ALL
SELECT
    p.Id AS PostId,
    p.Title,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS QuestionOwner,
    u.Reputation AS OwnerReputation,
    0 AS OwnerRecentBadges,
    p.CreationDate AS QuestionDate,
    p.ViewCount,
    p.Score AS QuestionScore,
    0 AS AnswerCount,
    0 AS AvgAnswerScore,
    NULL AS LatestAnswerDate,
    NULL AS TAGs,
    0 AS Commenters,
    NULL AS LastCommentDate,
    0 AS VoteCount,
    0 AS Upvotes,
    0 AS Downvotes,
    'No Answers or Votes' AS PopularityTag,
    'Orphaned' AS EngagementTag
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
    AND p.CreationDate > NOW() - INTERVAL '1 year'
    AND p.AnswerCount IS NULL
    AND NOT EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id)
    AND p.ViewCount < 10
ORDER BY p.CreationDate DESC
LIMIT 20;