-- {"query": "2294.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1734} 

WITH RecursiveUserBadgeSummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        b.Class,
        COUNT(b.Id) OVER (PARTITION BY u.Id, b.Class) AS BadgeCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Class) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.TagBased = 0
    WHERE u.Reputation > 1000
), FilteredUsers AS (
    SELECT DISTINCT UserId, DisplayName, Reputation
    FROM RecursiveUserBadgeSummary
    WHERE BadgeCount >= 2 AND BadgeRank = 1
), PostsWithAggregates AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.Tags, '') AS Tags,
        u.DisplayName AS OwnerName,
        u.Reputation,
        COUNT(c.Id) AS CommentCount,
        MAX(ph.CreationDate) AS LastEditDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        ROW_NUMBER() OVER (
            PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC NULLS LAST
        ) AS PostRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.PostId = p.Id AND (c.Score IS NULL OR c.Score >= 0)
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
    WHERE p.CreationDate > '2022-01-01' 
        AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation, p.Tags
), DuplicateLinks AS (
    SELECT DISTINCT pl.PostId, pl.RelatedPostId
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId AND lt.Name = 'Duplicate'
), UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(b.Id) AS TotalBadges,
        SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8) AS TotalBountyStarted,
        MIN(u.CreationDate) AS FirstSeen,
        MAX(u.LastAccessDate) AS LastSeen,
        AVG(EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate))/86400) OVER () AS AvgUserLifeDays
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= u.CreationDate
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId IN (8,9)
    GROUP BY u.Id, u.DisplayName
), PostCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        COUNT(*) AS CloseVotes
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(NULLIF(ph.Comment, '') AS SMALLINT)
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
), TopQuestionsWithDuplicates AS (
    SELECT 
        pwa.Id,
        pwa.Title,
        pwa.OwnerUserId,
        pwa.Score,
        pwa.ViewCount,
        pwa.Tags,
        u.DisplayName AS OwnerName,
        COALESCE(pc.CloseReason, 'Open') AS CloseStatus,
        CASE WHEN dl.PostId IS NOT NULL THEN TRUE ELSE FALSE END AS IsDuplicate,
        LENGTH(pwa.Tags) - LENGTH(REPLACE(pwa.Tags, '<', '')) AS TagCount, -- crude count of tags
        ROW_NUMBER() OVER (PARTITION BY pwa.OwnerUserId ORDER BY pwa.Score DESC) AS UserTopQuestionRank
    FROM PostsWithAggregates pwa
    LEFT JOIN Users u ON u.Id = pwa.OwnerUserId
    LEFT JOIN PostCloseReasons pc ON pc.PostId = pwa.Id
    LEFT JOIN DuplicateLinks dl ON dl.PostId = pwa.Id
    WHERE pwa.PostTypeId = 1 AND pwa.PostRank <= 100
), CorrelatedAnswerStats AS (
    SELECT 
        ta.Id AS AnswerId,
        ta.ParentId AS QuestionId,
        ta.Score AS AnswerScore,
        ta.CreationDate AS AnswerDate,
        (SELECT MAX(p.Score) FROM Posts p WHERE p.ParentId = ta.ParentId) AS MaxAnswerScoreForQuestion,
        RANK() OVER (PARTITION BY ta.ParentId ORDER BY ta.Score DESC, ta.CreationDate ASC) AS AnswerRank,
        u.DisplayName AS AnswerOwner
    FROM Posts ta
    LEFT JOIN Users u ON u.Id = ta.OwnerUserId
    WHERE ta.PostTypeId = 2
)
SELECT 
    tq.Id AS QuestionId,
    tq.Title,
    tq.OwnerUserId,
    tq.OwnerName,
    tq.Score AS QuestionScore,
    tq.ViewCount,
    tq.Tags,
    tq.TagCount,
    tq.CloseStatus,
    tq.IsDuplicate,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.TotalBadges,
    uas.TotalBountyStarted,
    uas.FirstSeen,
    uas.LastSeen,
    aas.AnswerId,
    aas.AnswerScore,
    aas.AnswerRank,
    aas.MaxAnswerScoreForQuestion,
    aas.AnswerOwner,
    CONCAT_WS(' | ', 
        CASE WHEN tq.CloseStatus = 'Open' THEN 'Active' ELSE 'Closed' END,
        CASE WHEN aas.AnswerScore > COALESCE(tq.Score/2,0) THEN 'Popular Answer' ELSE 'Low scored answer' END,
        CASE WHEN tq.IsDuplicate THEN 'Duplicate Question' ELSE 'Original Question' END
    ) AS StatusSummary
FROM TopQuestionsWithDuplicates tq
INNER JOIN UserActivityWindow uas ON uas.UserId = tq.OwnerUserId
LEFT JOIN CorrelatedAnswerStats aas ON aas.QuestionId = tq.Id AND aas.AnswerRank = 1
WHERE uas.TotalBadges >= 3
ORDER BY uas.Reputation DESC NULLS LAST, tq.Score DESC
LIMIT 50
UNION ALL
SELECT 
    p.Id,
    p.Title,
    p.OwnerUserId,
    u.DisplayName,
    p.Score,
    p.ViewCount,
    COALESCE(p.Tags, '') AS Tags,
    LENGTH(COALESCE(p.Tags, '')) - LENGTH(REPLACE(COALESCE(p.Tags, ''), '<', '')) AS TagCount,
    'Archived' AS CloseStatus,
    FALSE AS IsDuplicate,
    0 AS QuestionCount,
    0 AS AnswerCount,
    0 AS TotalBadges,
    0 AS TotalBountyStarted,
    u.CreationDate AS FirstSeen,
    u.LastAccessDate AS LastSeen,
    NULL::int AS AnswerId,
    NULL::int AS AnswerScore,
    NULL::int AS AnswerRank,
    NULL::int AS MaxAnswerScoreForQuestion,
    NULL AS AnswerOwner,
    'Archived Post | No Activity' AS StatusSummary
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId IN (1,2) AND p.CreationDate < CURRENT_DATE - INTERVAL '5 years'
ORDER BY Score DESC NULLS LAST, ViewCount DESC NULLS LAST
LIMIT 50;
