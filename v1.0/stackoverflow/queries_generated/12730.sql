-- Performance benchmark query to analyze posts, users, and vote statistics

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(v.VoteTypeId = 2) AS UpVotes,  -- Assume VoteTypeId 2 is UpMod
        SUM(v.VoteTypeId = 3) AS DownVotes  -- Assume VoteTypeId 3 is DownMod
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        u.Id
),
PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.AcceptedAnswerId,
        COALESCE(u.DisplayName, 'Community') AS OwnerDisplayName
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.PostCount,
    us.QuestionCount,
    us.AnswerCount,
    us.UpVotes,
    us.DownVotes,
    ps.PostId,
    ps.Title,
    ps.CreationDate,
    ps.Score,
    ps.ViewCount,
    ps.CommentCount,
    ps.OwnerDisplayName
FROM 
    UserStats us
LEFT JOIN 
    PostStats ps ON us.UserId = ps.OwnerUserId
ORDER BY 
    us.PostCount DESC, us.UpVotes DESC;
