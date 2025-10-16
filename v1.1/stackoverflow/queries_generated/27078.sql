-- {"query": "27078.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1211} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(v.CreationDate) AS LastVoteDate,
		NTILE(10) OVER (ORDER BY u.Reputation DESC) AS Rank
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.DisplayName
), TopPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        COUNT(a.Id) AS AnswerCount,
        COUNT(c.Id) AS CommentCount,
        SUM(v.VoteTypeId = 2) AS UpVotes,
        SUM(v.VoteTypeId = 3) AS DownVotes,
		STRING_AGG(DISTINCT t.TagName, '><') OVER (PARTITION BY p.Id) AS TagList,
        DENSE_RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank
    FROM
        Posts p
    LEFT JOIN
        Posts a ON p.Id = a.ParentId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
	LEFT JOIN
		Tags t ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE
	p.PostTypeId = 1
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.Tags, p.AcceptedAnswerId
), ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount,
        MAX(p.LastActivityDate) AS LastActivityDate,
		ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate DESC) AS ActivityRank
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    WHERE
        u.LastAccessDate > NOW() - INTERVAL '30 days'
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.PostCount,
    ua.CommentCount,
    ua.VoteCount,
    ua.UpVoteCount,
    ua.DownVoteCount,
    ua.BadgeCount,
    ua.LastPostDate,
    ua.LastCommentDate,
    ua.LastVoteDate,
    ua.Rank,
    tp.PostId,
    tp.Title,
    tp.PostTypeId,
    tp.Score,
    tp.ViewCount,
    tp.AnswerCount,
    tp.CommentCount,
    tp.TagList
FROM
    UserActivity ua
JOIN
    ActiveUsers au ON ua.UserId = au.UserId
LEFT JOIN
    TopPosts tp ON ua.UserId = tp.OwnerUserId AND au.ActivityRank <= 5
WHERE
    ua.Rank <= 5
ORDER BY
    ua.Rank, tp.PostRank
	;
 