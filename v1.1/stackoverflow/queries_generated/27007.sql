-- {"query": "27007.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1633} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount
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
        u.Id, u.Reputation, u.CreationDate
),
PostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT ph.Id) AS HistoryCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount
),
TagAnalysis AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        COUNT(p.Id) AS RelatedPostCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViewCount,
        STRING_AGG(p.Title, ', ') AS RelatedPostTitles
    FROM
        Tags t
    LEFT JOIN
        Posts p ON t.Id = ANY(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), ''><''))
    GROUP BY
        t.Id, t.TagName, t.Count
)
SELECT
    ua.UserId,
    ua.Reputation,
    ua.UserCreationDate,
    ua.PostCount,
    ua.CommentCount,
    ua.VoteCount,
    ua.BadgeCount,
    pm.PostId,
    pm.PostTypeId,
    pm.PostCreationDate,
    pm.Score AS PostScore,
    pm.ViewCount,
    pm.AnswerCount,
    pm.CommentCount AS PostCommentCount,
    pm.FavoriteCount,
    pm.VoteCount AS PostVoteCount,
    pm.HistoryCount,
    pm.LastEditDate,
    ta.TagId,
    ta.TagName,
    ta.TagCount,
    ta.RelatedPostCount,
    ta.AvgPostScore,
    ta.TotalViewCount,
    ta.RelatedPostTitles,
    CASE
        WHEN pm.PostTypeId = 1 THEN 'Question'
        WHEN pm.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS PostTypeName,
    COALESCE(p.Title, 'No Title') AS PostTitle,
    COALESCE(p.Body, 'No Body') AS PostBody,
    COALESCE(u.DisplayName, 'Anonymous') AS UserDisplayName,
    COALESCE(u.LastAccessDate, 'Never') AS LastAccessDate,
    COALESCE(u.Views, 0) AS UserViews,
    COALESCE(u.UpVotes, 0) AS UserUpVotes,
    COALESCE(u.DownVotes, 0) AS UserDownVotes,
    COALESCE(p.OwnerDisplayName, 'Unknown') AS PostOwnerDisplayName
FROM
    UserActivity ua
LEFT JOIN
    PostMetrics pm ON ua.UserId = pm.OwnerUserId
LEFT JOIN
    TagAnalysis ta ON pm.PostId = ta.TagId
LEFT JOIN
    Posts p ON pm.PostId = p.Id
LEFT JOIN
  Users u ON u.Id = p.OwnerUserId
ORDER BY
    ua.Reputation DESC,
    pm.Score DESC,
    ta.TagCount DESC
LIMIT 100
UNION
SELECT ua.UserId, , ua.Reputation, ua.UserCreationDate, ua.PostCount, ua.CommentCount, ua.VoteCount, ua.BadgeCount, pm.PostId, pm.PostTypeId,pm.PostCreationDate,pm.Score AS PostScore, pm.ViewCount, pm.AnswerCount,pm.CommentCount AS PostCommentCount, pm.FavoriteCount,pm.reCount AS PostVoteCount,pm.HistoryCount, pm.LastEditDate,ta.TagId, ta.TagName, ta.TagCount, ta.RelatedPostCount,ta.AvgPostScore, ta.TotalViewCount, ta.RelatedPostTitles,CASE   WHEN pm.PostTypeId = 1 THEN 'Question'   WHEN pm.PostTypeId = 2 THEN 'Answer'   ELSE 'Other' END AS PostTypeName,COALESCE(p.Title, 'No Title') AS PostTitle, COALESCE(p.Body, 'No Body') AS PostBody,COALESCE(u.DisplayName, 'Anonymous') AS UserDisplayName, COALESCE(u.LastAccessDate, 'Never') AS LastAccessDate,COALESCE(u.Views, 0) AS UserViews, COALESCE(u.UpVotes, 0) AS UserUpVotes, COALESCE(u.DownVotes, 0) AS UserDownvotess,COALESCE(p.OwnerDisplayName, 'Unknown') AS PostOwnerDisplayName
FROM
   Users ua
LEFT JOIN
   PostMetrics pm ON ua.Reputation = pm.reCount
JOIN
   TagAnalysis ta ON pm.PostId = ta.TagId
LEFT JOIN
   Posts p ON pm.PostId = PostId
LEFT JOIN
   Users u ON u.User = p.OwnerUserId;
