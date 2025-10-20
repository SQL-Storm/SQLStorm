-- {"query": "35024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 765} 
WITH RecentQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
TopActiveTags AS (
    SELECT 
        unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName
    FROM 
        RecentQuestions
),
TagAggregate AS (
    SELECT 
        t.TagName,
        COUNT(*) AS QuestionCount
    FROM 
        TopActiveTags t
    GROUP BY 
        t.TagName
    ORDER BY 
        QuestionCount DESC
    LIMIT 10
),
QuestionsWithBadges AS (
    SELECT 
        rq.QuestionId,
        rq.Title,
        rq.CreationDate,
        rq.OwnerUserId,
        rq.OwnerName,
        rq.Score,
        rq.ViewCount,
        rq.AnswerCount,
        rq.Tags,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM 
        RecentQuestions rq
    LEFT JOIN 
        Badges b ON b.UserId = rq.OwnerUserId
    GROUP BY 
        rq.QuestionId, rq.Title, rq.CreationDate, rq.OwnerUserId, rq.OwnerName, rq.Score, rq.ViewCount, rq.AnswerCount, rq.Tags
),
AnswerDetails AS (
    SELECT 
        p.ParentId AS QuestionId,
        COUNT(*) AS AnswerTotal,
        MAX(p.Score) AS TopAnswerScore,
        AVG(p.Score) AS AvgAnswerScore
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 2
        AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
    GROUP BY 
        p.ParentId
)
SELECT 
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.OwnerUserId,
    q.OwnerName,
    q.Score AS QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    ta.TagName AS MainTag,
    q.BadgeCount,
    COALESCE(a.AnswerTotal, 0) AS AnswerTotal,
    COALESCE(a.TopAnswerScore, 0) AS TopAnswerScore,
    ROUND(COALESCE(a.AvgAnswerScore, 0),2) AS AvgAnswerScore,
    (
        SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.PostId = q.QuestionId
    ) AS CommentCount,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = q.QuestionId 
        AND v.VoteTypeId = 2
    ) AS UpVoteCount,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = q.QuestionId 
        AND v.VoteTypeId = 3
    ) AS DownVoteCount
FROM 
    QuestionsWithBadges q
JOIN LATERAL (
    SELECT 
        t.TagName
    FROM 
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) t(TagName)
    WHERE 
        t.TagName IN (SELECT TagName FROM TagAggregate)
    LIMIT 1
) ta ON true
LEFT JOIN 
    AnswerDetails a ON a.QuestionId = q.QuestionId
ORDER BY 
    q.Score DESC, q.ViewCount DESC
LIMIT 50;