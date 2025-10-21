-- {"query": "43085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 716} 

WITH UserReputationCTE AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        SUM(b.Class) AS TotalBadgeClasses,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
),
TopAnsweredQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.ViewCount,
        p.Score,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        ph.CreationDate AS LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn
    FROM 
        Posts p
    JOIN 
        PostHistory ph ON p.Id = ph.PostId
    WHERE 
        p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
),
PostActivity AS (
    SELECT 
        p.Id AS PostId,
        COUNT(DISTINCT ph.Id) AS EditCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        p.Id
)
SELECT 
    ur.UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.TotalBadgeClasses,
    ur.BadgeCount,
    ur.ReputationRank,
    taq.QuestionId,
    taq.Title,
    taq.ViewCount,
    taq.Score,
    taq.Tags,
    taq.AnswerCount,
    taq.FavoriteCount,
    pa.EditCount,
    pa.CommentCount,
    pa.UpvoteCount,
    pa.DownvoteCount
FROM 
    UserReputationCTE ur
JOIN 
    Posts p ON ur.UserId = p.OwnerUserId
JOIN 
    TopAnsweredQuestions taq ON p.Id = taq.QuestionId AND taq.rn = 1
JOIN 
    PostActivity pa ON taq.QuestionId = pa.PostId
WHERE 
    ur.ReputationRank <= 100
ORDER BY 
    ur.Reputation DESC, 
    taq.AnswerCount DESC, 
    pa.UpvoteCount DESC;
