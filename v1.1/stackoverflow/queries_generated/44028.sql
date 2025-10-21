-- {"query": "44028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 317}
SELECT 
    CONCAT(
        'SELECT p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Tags, '
        , GROUP_CONCAT(DISTINCT CONCAT('(SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = ', vt.Id, ') AS ', vt.Name))
        , ', (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount'
        , ', (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateCount'
        , ', (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId) AS BadgeCount'
        , ', (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id) AS HistoryCount'
        , ' FROM Posts p'
        , ' JOIN VoteTypes vt ON 1=1'
        , ' GROUP BY p.Id'
        , ' ORDER BY p.Score DESC, p.ViewCount DESC'
        , ' LIMIT 100'
    ) AS query;
