WITH UserReputationCTE AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        SUM(vb.VoteCount) AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Users u
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    LEFT JOIN 
        (SELECT PostId, COUNT(*) AS VoteCount FROM Votes GROUP BY PostId) vb ON vb.PostId = v.PostId
    GROUP BY 
        u.Id, u.DisplayName
),

QuestionDetailsCTE AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        COALESCE(p.CommentCount, 0) + COALESCE(p.AnswerCount, 0) AS InteractionScore
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
),

RichQuestions AS (
    SELECT 
        q.QuestionId,
        q.Title,
        t.TagName,
        u.Id AS OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        ur.TotalVotes,
        ur.UpVotes,
        ur.DownVotes,
        q.InteractionScore
    FROM 
        QuestionDetailsCTE q
    LEFT JOIN 
        Tags t ON POSITION(t.TagName IN REPLACE(REPLACE(REPLACE('<' || SUBSTRING(q.Title, 1, 1) || '', '<', ''), '>', ''), ',', '')) IS NOT NULL
    LEFT JOIN 
        Users u ON q.QuestionId = u.Id
    LEFT JOIN 
        UserReputationCTE ur ON u.Id = ur.UserId
)

SELECT 
    rq.QuestionId,
    rq.Title,
    rq.TagName,
    rq.OwnerDisplayName,
    rq.InteractionScore,
    rq.TotalVotes,
    rq.UpVotes,
    rq.DownVotes,
    COALESCE(ph.Comment, 'No Comments') AS LastComment
FROM 
    RichQuestions rq
LEFT JOIN 
    PostHistory ph ON rq.QuestionId = ph.PostId AND ph.PostHistoryTypeId = 2
WHERE 
    COALESCE(rq.TagName, 'Miscellaneous') IS NOT NULL
ORDER BY 
    rq.InteractionScore DESC, rq.TotalVotes DESC
LIMIT 10;