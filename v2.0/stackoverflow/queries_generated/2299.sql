-- {"query": "2299.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1686} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        0 AS Level,
        ARRAY[t.TagName] AS AncestorPath
    FROM Tags t
    WHERE t.IsRequired = 0

    UNION ALL

    SELECT
        tchild.Id,
        tchild.TagName,
        tchild.Count,
        tchild.ExcerptPostId,
        tchild.WikiPostId,
        r.Level + 1 AS Level,
        r.AncestorPath || tchild.TagName
    FROM Tags tchild
    JOIN RecursiveTagHierarchy r ON tchild.Count < r.Count AND NOT tchild.TagName = ANY(r.AncestorPath)
    WHERE tchild.IsRequired = 0
),
RecentBadgeUsers AS (
    SELECT
        b.UserId,
        u.DisplayName,
        COUNT(*) AS BadgeCount,
        MAX(b.Date) AS LastBadgeDate,
        STRING_AGG(DISTINCT b.Name, ',' ORDER BY b.Name) AS BadgeNames
    FROM Badges b
    JOIN Users u ON u.Id = b.UserId
    WHERE b.Date > NOW() - INTERVAL '1 year'
    GROUP BY b.UserId, u.DisplayName
),
QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Tags,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate) AS AnswerRank,
        u.Id AS OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        COALESCE(v.UpVotes,0) AS OwnerUpVotes,
        COALESCE(v.DownVotes,0) AS OwnerDownVotes,
        ARRAY_LENGTH(string_to_array(replace(replace(q.Tags, '<', ''), '>', '#'), '#'), 1) AS TagCount
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN LATERAL (
        SELECT
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
        WHERE v.UserId = u.Id
        GROUP BY v.UserId
    ) v ON TRUE
    WHERE q.PostTypeId = 1
),
CommentsSummary AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        BOOL_OR(c.UserId IS NULL) AS HasAnonymousCommenters
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    GROUP BY p.Id
),
ClosedQuestions AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS CloseDate,
        crt.Name AS CloseReason,
        ph.UserId,
        u.DisplayName AS CloserDisplayName
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INT)
    LEFT JOIN Users u ON u.Id = ph.UserId
    WHERE ph.PostHistoryTypeId = 10
),
DistinguishedAnswerers AS (
    SELECT
        a.OwnerUserId,
        u.DisplayName,
        COUNT(DISTINCT a.Id) AS NumAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.CreationDate) AS LastAnswerDate,
        RANK() OVER (ORDER BY COUNT(DISTINCT a.Id) DESC, AVG(a.Score) DESC) AS RankByAnswerCount
    FROM Posts a
    JOIN Users u ON u.Id = a.OwnerUserId
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId, u.DisplayName
),
TopQuestionsCTE AS (
    SELECT DISTINCT ON (q.Id)
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.Tags,
        a.Id AS AcceptedAnswerId,
        au.DisplayName AS AcceptedAnswerer,
        au.Reputation AS AcceptedAnswererRep
    FROM Posts q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId
    LEFT JOIN Users au ON au.Id = a.OwnerUserId
    WHERE q.PostTypeId = 1 AND q.AnswerCount >= 5 AND q.Score > 0
    ORDER BY q.Id, a.Score DESC NULLS LAST
)

SELECT
    q.Title,
    q.CreationDate::date AS QuestionDate,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    q.TagCount,
    ts.CommentCount,
    ts.AvgCommentScore,
    ts.LastCommentDate,
    ts.HasAnonymousCommenters,
    dq.RankByAnswerCount,
    da.NumAnswers AS DistAnswererAnswers,
    da.AvgAnswerScore AS DistAnswererAvgScore,
    dq.DisplayName AS QuestionOwner,
    dq.OwnerReputation,
    dq.OwnerUpVotes,
    dq.OwnerDownVotes,
    ARRAY_TO_STRING(RecursiveTagHierarchy.AncestorPath, ' > ') AS TagHierarchyPath,
    rq.CloseDate,
    rq.CloseReason,
    rq.CloserDisplayName,
    rb.BadgeCount,
    rb.BadgeNames,
    tq.AcceptedAnswerId,
    tq.AcceptedAnswerer,
    tq.AcceptedAnswererRep,
    CONCAT('Tags: ', COALESCE(q.Tags, '<none>')) AS TagsFormatted,
    CASE 
        WHEN q.Score > 100 THEN 'Hot'
        WHEN q.Score BETWEEN 50 AND 100 THEN 'Trending'
        ELSE 'Normal'
    END AS PopularityCategory,
    ROW_NUMBER() OVER (PARTITION BY dq.RankByAnswerCount ORDER BY q.Score DESC) AS RowInRank
FROM QuestionAnswerStats q
LEFT JOIN CommentsSummary ts ON ts.PostId = q.QuestionId
LEFT JOIN DistinguishedAnswerers da ON da.OwnerUserId = q.OwnerUserId
LEFT JOIN Users dq ON dq.Id = q.OwnerUserId
LEFT JOIN RecursiveTagHierarchy ON RecursiveTagHierarchy.TagName = split_part(q.Tags, '><', 1)
LEFT JOIN ClosedQuestions rq ON rq.PostId = q.QuestionId
LEFT JOIN RecentBadgeUsers rb ON rb.UserId = q.OwnerUserId
LEFT JOIN TopQuestionsCTE tq ON tq.Id = q.QuestionId
WHERE q.TagCount > 0 AND dq.Reputation >= 1000 
  AND (rq.CloseDate IS NULL OR rq.CloseDate > NOW() - INTERVAL '6 months')
ORDER BY q.Score DESC, q.ViewCount DESC
LIMIT 100

UNION

SELECT
    'Summary' AS Title,
    NULL::date AS QuestionDate,
    SUM(q.ViewCount) AS ViewCount,
    AVG(q.Score) AS Score,
    SUM(q.AnswerCount) AS AnswerCount,
    AVG(q.TagCount)::int AS TagCount,
    SUM(ts.CommentCount),
    AVG(ts.AvgCommentScore),
    MAX(ts.LastCommentDate),
    FALSE,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    'Aggregate' AS TagsFormatted,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM QuestionAnswerStats q
LEFT JOIN CommentsSummary ts ON ts.PostId = q.QuestionId
WHERE q.OwnerReputation >= 1000
