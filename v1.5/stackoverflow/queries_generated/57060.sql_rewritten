-- {"query": "57060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1110} 
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(p.CreationDate) AS LastPostDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id, u.Reputation, u.DisplayName
),
PostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        COALESCE(v.UpVotes, 0) AS UpVotes,
        COALESCE(v.DownVotes, 0) AS DownVotes,
        COALESCE(v.Views, 0) AS Views
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
	LEFT JOIN (SELECT PostId,
	          SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
	          SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
			  Count(UserId) as Views
			  FROM Votes GROUP BY PostId) v ON p.Id = v.PostId
    WHERE
        p.PostTypeId IN (1, 2)
),
CommentActivity AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalComments,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
        Comments c
    GROUP BY
        c.PostId
),
TagMetrics AS (
    SELECT
        p.Id AS PostId,
        p.Tags,
        t.TagName,
        t.Count AS TagCount
    FROM
        Posts p
    LEFT JOIN
        Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE
        p.PostTypeId = 1
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.LastPostDate,
    pm.PostId,
    pm.PostTypeId,
    pm.CreationDate,
    pm.Score,
    pm.ViewCount,
    pm.AnswerCount,
    pm.CommentCount,
    pm.FavoriteCount,
    pm.OwnerDisplayName,
    pm.UpVotes,
    pm.DownVotes,
    pm.Views,
    ca.TotalComments,
    ca.LastCommentDate,
    tm.TagName,
    tm.TagCount
FROM
    UserActivity ua
JOIN
    PostMetrics pm ON ua.UserId = pm.OwnerUserId
LEFT JOIN
    CommentActivity ca ON pm.PostId = ca.PostId
LEFT JOIN
    TagMetrics tm ON pm.PostId = tm.PostId
WHERE
   ua.UserId In  (SELECT u.Id
              	  FROM Users u
				    JOIN Votes v ON u.Id = v.UserId
	 			  	WHERE v.PostId IN (SELECT PostId
											FROM Votes
											WHERE VoteTypeId  in (2, 3, 6, 7, 8, 9)
											GROUP BY PostId
											HAVING COUNT(Id) > 5)
				   GROUP BY u.Id
				   HAVING COUNT(v.Id) > 10)
ORDER BY
    ua.Reputation DESC,
    pm.Score DESC,
    ca.TotalComments DESC,
    tm.TagCount DESC;