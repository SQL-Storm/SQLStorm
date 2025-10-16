-- {"query": "18017.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1454} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserContributionScores AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.AnswerCount, 0) ELSE 0 END) AS TotalAnsweredQuestions,
        MAX(p.CreationDate) AS LastQuestionDate,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
        (
            SELECT COUNT(*)
            FROM Posts p2
            WHERE p2.OwnerUserId = u.Id
            AND p2.ClosedDate IS NOT NULL
        ) AS ClosedPostCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
HotQuestions AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) as RankScoreView,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as RowNumCreation
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.AnswerCount > 0 AND p.ClosedDate IS NULL
),
AnswerQuality AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        q.Score AS QuestionScore,
        q.CreationDate AS QuestionCreationDate,
        CASE
            WHEN a.Score > q.Score THEN 'Better'
            WHEN a.Score < q.Score THEN 'Worse'
            ELSE 'Same'
        END AS ScoreComparison,
        a.OwnerUserId AS AnswerOwnerUserId,
        q.OwnerUserId AS QuestionOwnerUserId
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 AND q.PostTypeId = 1
)
SELECT
    ucs.UserId,
    ucs.DisplayName,
    ucs.QuestionCount,
    ucs.AnswerCount,
    ucs.TotalAnsweredQuestions,
    ucs.LastQuestionDate,
    ucs.CommentCount,
    ucs.UpVoteCount,
    ucs.DownVoteCount,
    ucs.BadgeCount,
    ucs.AvgPostScore,
    ucs.ClosedPostCount,
    hq.Title AS HottestQuestionTitle,
    hq.Score AS HottestQuestionScore,
    aq.AnswerId,
    aq.QuestionId,
    aq.AnswerScore,
    aq.AnswerCreationDate,
    aq.ScoreComparison,
    CASE
        WHEN UPPER(REPLACE(ucs.DisplayName, ' ', '')) LIKE '%[AEIOU]%' THEN 'VOWEL_IN_NAME'
        WHEN ucs.UpVoteCount > ucs.DownVoteCount * 1.5 THEN 'NET_POSITIVE_VOTES'
        WHEN ucs.CommentCount > ucs.AnswerCount * 2 THEN 'HIGH_COMMENT_RATIO'
        ELSE 'STANDARD'
    END AS UserClassification,
    COALESCE(
        (SELECT Name FROM PostHistoryTypes WHERE Id = (SELECT MIN(PostHistoryTypeId) FROM PostHistory WHERE UserId = ucs.UserId)),
        'NoHistory'
    ) AS FirstHistoryType
FROM UserContributionScores ucs
LEFT JOIN HotQuestions hq ON hq.RankScoreView = 1
LEFT JOIN AnswerQuality aq ON aq.AnswerOwnerUserId = ucs.UserId
WHERE ucs.QuestionCount > 10
AND EXISTS (
    SELECT 1
    FROM Posts p_sub
    WHERE p_sub.OwnerUserId = ucs.UserId
    AND p_sub.Title IS NOT NULL
    AND LENGTH(p_sub.Title) > 50
)
UNION
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.QuestionCount,
    ues.AnswerCount,
    ues.TotalAnsweredQuestions,
    ues.LastQuestionDate,
    ues.CommentCount,
    ues.UpVoteCount,
    ues.DownVoteCount,
    ues.BadgeCount,
    ues.AvgPostScore,
    ues.ClosedPostCount,
    NULL AS HottestQuestionTitle,
    NULL AS HottestQuestionScore,
    NULL AS AnswerId,
    NULL AS QuestionId,
    NULL AS AnswerScore,
    NULL AS AnswerCreationDate,
    NULL AS ScoreComparison,
    'LOW_ACTIVITY' AS UserClassification,
    'NoHistory' AS FirstHistoryType
FROM UserContributionScores ucs
LEFT JOIN (
    SELECT UserId, DisplayName, QuestionCount, AnswerCount, TotalAnsweredQuestions, LastQuestionDate, CommentCount, UpVoteCount, DownVoteCount, BadgeCount, AvgPostScore, ClosedPostCount
    FROM UserContributionScores
    WHERE QuestionCount <= 5 AND AnswerCount <= 5 AND CommentCount <= 10
) AS ues ON ucs.UserId = ues.UserId
WHERE ucs.QuestionCount <= 5 AND ucs.AnswerCount <= 5 AND ucs.CommentCount <= 10;
