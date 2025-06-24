
WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS Downvotes,
        COALESCE(PLE.Likes, 0) AS RelatedLikes,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 
            ELSE 0 
        END AS HasAcceptedAnswer
    FROM 
        Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN (
        SELECT 
            PostId,
            COUNT(*) AS Likes 
        FROM 
            PostLinks pl
        WHERE 
            pl.LinkTypeId = 1 
        GROUP BY 
            PostId
    ) PLE ON p.Id = PLE.PostId
    GROUP BY 
        p.Id, p.AcceptedAnswerId, PLE.Likes
),
TopPosts AS (
    SELECT 
        ps.PostId,
        ps.CommentCount,
        ps.Upvotes,
        ps.Downvotes,
        ROW_NUMBER() OVER (ORDER BY ps.Upvotes DESC, ps.CommentCount DESC) AS Rank
    FROM 
        PostStats ps
    WHERE 
        ps.HasAcceptedAnswer = 1
),
Benchmark AS (
    SELECT 
        tp.PostId,
        tp.CommentCount,
        tp.Upvotes,
        tp.Downvotes,
        COALESCE(NULLIF(tp.Upvotes - tp.Downvotes, 0), -1) AS VoteBalance
    FROM 
        TopPosts tp
    WHERE 
        tp.Rank <= 10
)
SELECT 
    b.PostId,
    b.CommentCount,
    b.Upvotes,
    b.Downvotes,
    b.VoteBalance,
    CASE 
        WHEN b.VoteBalance < 0 THEN 'Negative'
        WHEN b.VoteBalance = 0 THEN 'Neutral'
        ELSE 'Positive' 
    END AS VoteStatus,
    'Post ID: ' + CAST(b.PostId AS VARCHAR(10)) + ' - Vote Balance: ' + CAST(b.VoteBalance AS VARCHAR(10)) AS Summary
FROM 
    Benchmark b
ORDER BY 
    b.VoteBalance DESC;
