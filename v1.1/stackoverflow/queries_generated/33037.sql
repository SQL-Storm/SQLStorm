-- {"query": "33037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 465} 
SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    p.Id AS PostId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    u.Reputation AS OwnerReputation,
    u.CreationDate AS UserCreationDate,
    u.Location,
    u.UpVotes,
    u.DownVotes,
    u.Views AS UserViews,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCount,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesCount,
    COUNT(DISTINCT bv.Id) AS BadgesCount,
    COUNT(DISTINCT l.Id) AS LinkCount,
    ARRAY_AGG(DISTINCT tt.Name) AS LinkTypes,
    COUNT(DISTINCT ht.Id) AS RevisionCount,
    COUNT(DISTINCT ch.Id) AS CommentHistoryCount
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Badges bv ON bv.UserId = p.OwnerUserId
LEFT JOIN PostLinks l ON l.PostId = p.Id
LEFT JOIN LinkTypes tt ON l.LinkTypeId = tt.Id
LEFT JOIN PostHistory ht ON ht.PostId = p.Id
LEFT JOIN PostHistoryTypes htType ON ht.PostHistoryTypeId = htType.Id
LEFT JOIN Comments ch ON ch.PostId = p.Id AND ch.UserId IS NOT NULL
GROUP BY
    p.PostTypeId,
    pt.Name,
    p.Id,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    u.Reputation,
    u.CreationDate,
    u.Location,
    u.UpVotes,
    u.DownVotes,
    u.Views;