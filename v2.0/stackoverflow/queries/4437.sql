-- {"query": "4437.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1154} 
WITH QuestionDetails AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS QuestionRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
    GROUP BY
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        u.DisplayName,
        u.Reputation
),
AnswerDetails AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.CreationDate AS AnswerCreationDate,
        ua.DisplayName AS AnswerOwnerDisplayName,
        ua.Reputation AS AnswerOwnerReputation,
        a.Score AS AnswerScore,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank,
        CASE WHEN p.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAcceptedAnswer
    FROM Posts a
    JOIN Users ua ON a.OwnerUserId = ua.Id
    JOIN Posts p ON a.ParentId = p.Id
    WHERE a.PostTypeId = 2
),
CommentActivity AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT ph.Id) AS PostHistoryCount,
        MAX(ph.CreationDate) AS LastPostHistoryDate,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation
)
SELECT
    qd.QuestionId,
    qd.QuestionTitle,
    qd.OwnerDisplayName,
    qd.OwnerReputation,
    qd.QuestionCreationDate,
    qd.AnswerCount,
    qd.UpVoteCount,
    qd.DownVoteCount,
    ad.AnswerId,
    ad.AnswerOwnerDisplayName,
    ad.AnswerOwnerReputation,
    ad.AnswerScore,
    ad.AnswerRank,
    ad.IsAcceptedAnswer,
    ca.CommentCount,
    ca.LastCommentDate,
    uas.PostHistoryCount,
    uas.LastPostHistoryDate,
    uas.BadgeCount,
    CASE
        WHEN qd.QuestionRank <= 100 THEN 'Top 100 Questions'
        WHEN qd.QuestionRank <= 500 THEN 'Next 400 Questions'
        ELSE 'Other Questions'
    END AS QuestionCategory,
    COALESCE(qd.OwnerDisplayName, 'Anonymous') AS DisplayNameOrAnonymous,
    CASE
        WHEN ad.AnswerRank = 1 AND ad.IsAcceptedAnswer = 1 THEN 'Accepted and Highest Rated Answer'
        WHEN ad.IsAcceptedAnswer = 1 THEN 'Accepted Answer'
        WHEN ad.AnswerRank = 1 THEN 'Highest Rated Answer'
        ELSE 'Other Answer'
    END AS AnswerQualityIndicator,
    DATE_PART('year', qd.QuestionCreationDate) AS QuestionYear,
    DATE_PART('month', qd.QuestionCreationDate) AS QuestionMonth,
    CASE
        WHEN qd.OwnerReputation > 10000 THEN 'High Reputation'
        WHEN qd.OwnerReputation > 1000 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
    END AS ReputationTier
FROM QuestionDetails qd
LEFT JOIN AnswerDetails ad ON qd.QuestionId = ad.QuestionId
LEFT JOIN CommentActivity ca ON qd.QuestionId = ca.PostId
LEFT JOIN UserActivitySummary uas ON qd.OwnerUserId = uas.UserId
WHERE qd.QuestionCreationDate >= '2023-01-01'
AND qd.OwnerReputation > 50
AND (qd.AnswerCount > 0 OR qd.QuestionRank <= 10)
ORDER BY qd.QuestionCreationDate DESC, ad.AnswerRank ASC;