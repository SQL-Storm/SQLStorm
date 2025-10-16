-- {"query": "5078.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1158} 
WITH recent_questions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        u.DisplayName AS OwnerName,
        RANK() OVER (ORDER BY p.CreationDate DESC) AS q_rank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
top_answers AS (
    SELECT 
        a.ParentId AS QuestionId,
        a.Id AS AnswerId,
        a.Body AS AnswerBody,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerOwnerId,
        ua.DisplayName AS AnswerOwnerName,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS ans_rank 
    FROM Posts a
    LEFT JOIN Users ua ON a.OwnerUserId = ua.Id
    WHERE a.PostTypeId = 2
),
question_activity AS (
    SELECT 
        q.QuestionId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MIN(c.CreationDate) AS FirstCommentDate,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes
    FROM recent_questions q
    LEFT JOIN Comments c ON q.QuestionId = c.PostId
    LEFT JOIN Votes v ON q.QuestionId = v.PostId
    GROUP BY q.QuestionId
),
tag_info AS (
    SELECT 
        rq.QuestionId,
        unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) AS TagName
    FROM recent_questions rq
),
tag_stats AS (
    SELECT 
        ti.QuestionId,
        array_agg(ti.TagName ORDER BY t.Count DESC, ti.TagName) AS TagList,
        SUM(t.Count) AS TotalTagUsage
    FROM tag_info ti
    LEFT JOIN Tags t ON ti.TagName = t.TagName
    GROUP BY ti.QuestionId
),
accepted_answerers AS (
    SELECT 
        p.Id AS QuestionId,
        a.OwnerUserId AS AcceptedAnswererId,
        u.DisplayName AS AcceptedAnswererName
    FROM Posts p
    INNER JOIN Posts a ON p.AcceptedAnswerId = a.Id
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
question_closures AS (
    SELECT 
        ph.PostId AS QuestionId,
        MAX(ph.CreationDate) AS ClosedDate,
        crt.Name AS CloseReason
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON 
        ph.PostHistoryTypeId = 10 AND ph.Comment::int = crt.Id -- careful: Comment holds CloseReasonId
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
first_gold_badge AS (
    SELECT 
        b.UserId,
        MIN(b.Date) AS FirstGoldBadgeDate,
        MIN(b.Name) AS FirstGoldBadgeName
    FROM Badges b
    WHERE b.Class = 1 -- Gold
    GROUP BY b.UserId
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.OwnerUserId,
    rq.OwnerName,
    CASE 
        WHEN qclose.ClosedDate IS NOT NULL 
        THEN CONCAT('Closed at ', qclose.ClosedDate::date, ' (', COALESCE(qclose.CloseReason, 'Unknown reason'), ')')
        ELSE 'Open'
    END AS Status,
    rq.Score,
    rq.ViewCount,
    rq.AnswerCount,
    COALESCE(ta.AnswerId, -1) AS TopAnswerId,
    ta.AnswerOwnerName AS TopAnswerer,
    ta.AnswerScore,
    qa.CommentCount,
    qa.VoteCount,
    qa.NetVotes,
    qa.FirstCommentDate,
    qa.LastCommentDate,
    ts.TagList AS Tags,
    ts.TotalTagUsage,
    aa.AcceptedAnswererName,
    fb.FirstGoldBadgeName,
    fb.FirstGoldBadgeDate,
    CASE 
        WHEN fb.FirstGoldBadgeDate IS NOT NULL 
             AND rbq.CreationDate < fb.FirstGoldBadgeDate 
        THEN 'Asked before gold badge'
        WHEN fb.FirstGoldBadgeDate IS NOT NULL 
             AND rbq.CreationDate >= fb.FirstGoldBadgeDate 
        THEN 'Asked after gold badge'
        ELSE 'No gold badge'
    END AS BadgeStatus
FROM recent_questions rq
LEFT JOIN question_activity qa ON rq.QuestionId = qa.QuestionId
LEFT JOIN tag_stats ts ON rq.QuestionId = ts.QuestionId
LEFT JOIN top_answers ta ON 
    ta.QuestionId = rq.QuestionId
    AND ta.ans_rank = 1
LEFT JOIN accepted_answerers aa ON rq.QuestionId = aa.QuestionId
LEFT JOIN question_closures qclose ON rq.QuestionId = qclose.QuestionId
LEFT JOIN first_gold_badge fb ON rq.OwnerUserId = fb.UserId
LEFT JOIN recent_questions rbq ON rq.QuestionId = rbq.QuestionId
ORDER BY rq.q_rank
LIMIT 100;