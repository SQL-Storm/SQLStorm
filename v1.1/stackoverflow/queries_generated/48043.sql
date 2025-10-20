-- {"query": "48043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 989} 

WITH PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        COUNT(DISTINCT c.Id) AS CommentCountDistinct,
        COUNT(DISTINCT ph.Id) AS PostHistoryCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT pl.Id) AS PostLinkCount,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC) AS RankByPopularity,
        ROW_NUMBER() OVER (ORDER BY p.AnswerCount DESC, p.Score DESC) AS RankByAnswers,
        ROW_NUMBER() OVER (ORDER BY p.CommentCount DESC, p.Score DESC) AS RankByComments
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
    WHERE
        p.PostTypeId = 1 -- Questions only
        AND p.CreationDate >= '2023-01-01'
        AND p.CreationDate < '2024-01-01'
    GROUP BY
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT p.Id) AS PostCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RankByReputation
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        u.Id > 0 -- Exclude community user and other system users
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        u.UpVotes,
        u.DownVotes
)
SELECT
    pe.PostId,
    pe.Title,
    pe.PostCreationDate,
    pe.PostScore,
    pe.PostViewCount,
    pe.AnswerCount,
    pe.CommentCountDistinct,
    pe.PostHistoryCount,
    pe.VoteCount,
    pe.UpVotes,
    pe.DownVotes,
    pe.PostLinkCount,
    pe.RankByPopularity,
    pe.RankByAnswers,
    pe.RankByComments,
    ua.UserId,
    ua.DisplayName AS OwnerDisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.UserViews,
    ua.UserUpVotes,
    ua.UserDownVotes,
    ua.BadgeCount,
    ua.PostCount,
    ua.RankByReputation,
    (pe.PostScore * 10 + pe.PostViewCount * 2 + pe.AnswerCount * 5 + pe.CommentCountDistinct * 1 + ua.Reputation * 0.1) AS CompositeScore
FROM
    PostEngagement pe
JOIN
    Posts p ON pe.PostId = p.Id -- Join back to Posts to get OwnerUserId
JOIN
    UserActivity ua ON p.OwnerUserId = ua.UserId
ORDER BY
    CompositeScore DESC
LIMIT 100;
