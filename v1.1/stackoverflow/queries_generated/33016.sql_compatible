SELECT 
    p.Id,
    p.PostTypeId,
    pt.Name AS PostTypeName,
    p.Title,
    p.CreationDate,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate)) AS AgeInSeconds,
    p.Body,
    p.Score,
    p.ViewCount,
    array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) AS TagCount,
    p.AnswerCount,
    p.CommentCount AS PostCommentCount,
    p.FavoriteCount,
    COALESCE(vot.upvote_count, 0) AS UpvoteCount,
    COALESCE(vot.downvote_count, 0) AS DownvoteCount,
    COALESCE(uc.Reputation, 0) AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    b.Name AS BadgeName,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT pl.RelatedPostId) AS LinkedPosts,
    ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TagNames,
    COUNT(DISTINCT gh.Id) AS HistoryEventCount
FROM 
    Posts p
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Badges b ON b.UserId = u.Id
LEFT JOIN 
    (
        SELECT 
            PostId, 
            COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS upvote_count,
            COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS downvote_count
        FROM 
            Votes
        GROUP BY 
            PostId
    ) vot ON p.Id = vot.PostId
LEFT JOIN 
    (
        SELECT 
            Id AS OwnerUserId, 
            Reputation
        FROM 
            Users
    ) uc ON p.OwnerUserId = uc.OwnerUserId
LEFT JOIN 
    Comments c ON c.PostId = p.Id
LEFT JOIN 
    PostLinks pl ON pl.PostId = p.Id
LEFT JOIN 
    Tags t ON p.Tags LIKE ('%<' || t.TagName || '>%')
LEFT JOIN 
    PostHistory gh ON gh.PostId = p.Id
WHERE 
    p.PostTypeId IN (1, 2)
GROUP BY 
    p.Id,
    p.PostTypeId,
    pt.Name,
    p.Title,
    p.CreationDate,
    p.Body,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    vot.upvote_count,
    vot.downvote_count,
    uc.Reputation,
    u.DisplayName,
    u.CreationDate,
    u.LastAccessDate,
    b.Name
ORDER BY 
    p.CreationDate DESC
LIMIT 100;