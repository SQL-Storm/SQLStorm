-- {"query": "44003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 6882, "output_tokens": 2474} 
WITH cte AS (
    SELECT 
        p.Id, 
        p.PostTypeId, 
        p.CreationDate, 
        p.OwnerUserId, 
        p.LastEditorUserId, 
        p.LastEditDate, 
        p.LastActivityDate, 
        p.AnswerCount, 
        p.CommentCount, 
        p.FavoriteCount, 
        p.ClosedDate, 
        p.CommunityOwnedDate, 
        u1.Reputation AS OwnerReputation, 
        u1.DisplayName AS OwnerDisplayName, 
        u2.Reputation AS EditorReputation, 
        u2.DisplayName AS EditorDisplayName
    FROM Posts p
    LEFT JOIN Users u1 ON p.OwnerUserId = u1.Id
    LEFT JOIN Users u2 ON p.LastEditorUserId = u2.Id
),
post_history AS (
    SELECT 
        ph.Id, 
        ph.PostId, 
        ph.PostHistoryTypeId, 
        ph.CreationDate, 
        ph.UserId, 
        ph.UserDisplayName, 
        ph.Comment, 
        ph.Text
    FROM PostHistory ph
    WHERE ph.PostId IN (SELECT Id FROM cte)
),
post_links AS (
    SELECT 
        pl.Id, 
        pl.CreationDate, 
        pl.PostId, 
        pl.RelatedPostId, 
        pl.LinkTypeId
    FROM PostLinks pl
    WHERE pl.PostId IN (SELECT Id FROM cte) OR pl.RelatedPostId IN (SELECT Id FROM cte)
),
post_votes AS (
    SELECT 
        v.Id, 
        v.PostId, 
        v.VoteTypeId, 
        v.UserId, 
        v.CreationDate, 
        v.BountyAmount
    FROM Votes v
    WHERE v.PostId IN (SELECT Id FROM cte)
),
post_comments AS (
    SELECT 
        c.Id, 
        c.PostId, 
        c.Score, 
        c.Text, 
        c.CreationDate, 
        c.UserDisplayName, 
        c.UserId
    FROM Comments c
    WHERE c.PostId IN (SELECT Id FROM cte)
)
SELECT 
    cte.Id, 
    cte.PostTypeId, 
    cte.CreationDate, 
    cte.OwnerUserId, 
    cte.LastEditorUserId, 
    cte.LastEditDate, 
    cte.LastActivityDate, 
    cte.AnswerCount, 
    cte.CommentCount, 
    cte.FavoriteCount, 
    cte.ClosedDate, 
    cte.CommunityOwnedDate, 
    cte.OwnerReputation, 
    cte.OwnerDisplayName, 
    cte.EditorReputation, 
    cte.EditorDisplayName, 
    post_history.Id AS HistoryId, 
    post_history.PostHistoryTypeId, 
    post_history.CreationDate AS HistoryCreationDate, 
    post_history.UserId AS HistoryUserId, 
    post_history.UserDisplayName AS HistoryUserDisplayName, 
    post_history.Comment AS HistoryComment, 
    post_history.Text AS HistoryText, 
    post_links.Id AS LinkId, 
    post_links.CreationDate AS LinkCreationDate, 
    post_links.RelatedPostId, 
    post_links.LinkTypeId, 
    post_votes.Id AS VoteId, 
    post_votes.VoteTypeId, 
    post_votes.UserId AS VoteUserId, 
    post_votes.CreationDate AS VoteCreationDate, 
    post_votes.BountyAmount, 
    post_comments.Id AS CommentId, 
    post_comments.Score AS CommentScore, 
    post_comments.Text AS CommentText, 
    post_comments.CreationDate AS CommentCreationDate, 
    post_comments.UserDisplayName AS CommentUserDisplayName, 
    post_comments.UserId AS CommentUserId
FROM cte
LEFT JOIN post_history ON cte.Id = post_history.PostId
LEFT JOIN post_links ON cte.Id = post_links.PostId OR cte.Id = post_links.RelatedPostId
LEFT JOIN post_votes ON cte.Id = post_votes.PostId
LEFT JOIN post_comments ON cte.Id = post_comments.PostId
ORDER BY cte.Id, post_history.CreationDate, post_links.CreationDate, post_votes.CreationDate, post_comments.CreationDate;