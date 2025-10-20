-- {"query": "14095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 224160, "output_tokens": 98383} 
WITH cte AS (
    SELECT 
        p.Id AS PostId, 
        p.PostTypeId, 
        p.OwnerUserId, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        p.CommentCount, 
        p.FavoriteCount, 
        p.CommunityOwnedDate, 
        p.ClosedDate,
        CASE WHEN p.ClosedDate IS NOT NULL THEN c.Name ELSE NULL END AS CloseReason,
        COALESCE(DATEDIFF(p.ClosedDate, p.CreationDate), 0) AS ClosureDays,
        COALESCE(DATEDIFF(ISNULL(p.AnswerCount, 0), 1), 0) AS AnswerDays,
        COALESCE(DATEDIFF(ISNULL(p.CommunityOwnedDate, '9999-12-31'), p.CreationDate), 0) AS CommunityOwnedDays,
        COALESCE(DATEDIFF(ISNULL(p.ClosedDate, '9999-12-31'), ISNULL(p.CommunityOwnedDate, '9999-12-31')), 0) AS ClosureDaysSinceOwnership,
        COALESCE(DATEDIFF(ISNULL(p.ClosedDate, '9999-12-31'), ISNULL(p.AcceptedAnswerId, 0)), 0) AS ClosureDaysSinceAcceptedAnswer,
        COALESCE(DATEDIFF(ISNULL(p.ClosedDate, '9999-12-31'), ISNULL(p.LastEditorUserId, 0)), 0) AS ClosureDaysSinceLastEdit,
        COALESCE(DATEDIFF(ISNULL(p.ClosedDate, '9999-12-31'), ISNULL(p.LastActivityDate, p.CreationDate)), 0) AS ClosureDaysSinceLastActivity,
        COALESCE(DATEDIFF(ISNULL(p.ClosedDate, '9999-12-31'), ISNULL(p.LastAccessDate, p.CreationDate)), 0) AS ClosureDaysSinceLastAccess,
        COALESCE(DATEDIFF(ISNULL(p.ClosedDate, '9999-12-31'), ISNULL(p.LastEditDate, p.CreationDate)), 0) AS ClosureDaysSinceLastEdit,
        COALESCE(DATEDIFF(ISNULL(p.ClosedDate, '9999-12-31'), ISNULL(p.CreationDate, '9999-12-31')), 0) AS ClosureDaysSinceCreation,
        COALESCE(DATEDIFF(ISNULL(p.AnswerCount, 0), 1), 0) AS AnswerDays,
        COALESCE(DATEDIFF(ISNULL(p.FavoriteCount, 0), 1), 0) AS FavoriteDays,
        COALESCE(DATEDIFF(ISNULL(p.ViewCount, 0), 1), 0) AS ViewDays,
        COALESCE(DATEDIFF(ISNULL(p.CommentCount, 0), 1), 0) AS CommentDays,
        COALESCE(DATEDIFF(ISNULL(p.Score, 0), 1), 0) AS ScoreDays,
        COALESCE(DATEDIFF(ISNULL(p.OwnerUserId, 0), 1), 0) AS OwnerUserDays,
        COALESCE(DATEDIFF(ISNULL(p.LastEditorUserId, 0), 1), 0) AS LastEditorUserDays,
        COALESCE(DATEDIFF(ISNULL(p.AcceptedAnswerId, 0), 1), 0) AS AcceptedAnswerDays,
        COALESCE(DATEDIFF(ISNULL(p.ParentId, 0), 1), 0) AS ParentPostDays,
        COALESCE(DATEDIFF(ISNULL(p.CommunityOwnedDate, '9999-12-31'), ISNULL(p.CreationDate, '9999-12-31')), 0) AS CommunityOwnedDays
    FROM Posts p
    LEFT JOIN CloseReasonTypes c ON p.ClosedDate IS NOT NULL AND p.ClosedDate = (SELECT ph.CreationDate 
                                                                                   FROM PostHistory ph
                                                                                   WHERE ph.PostId = p.Id 
                                                                                     AND ph.PostHistoryTypeId = 10
                                                                                   ORDER BY ph.CreationDate
                                                                                   LIMIT 1)
                                   AND p.ClosedDate = (SELECT ph.CreationDate
                                                       FROM PostHistory ph
                                                       WHERE ph.PostId = p.Id
                                                         AND ph.PostHistoryTypeId = 10
                                                       ORDER BY ph.CreationDate
                                                       LIMIT 1)
                                   AND c.Id = CAST(ph.Comment AS INT)
)
SELECT 
    PostId, 
    PostTypeId, 
    OwnerUserId,
    Score, 
    ViewCount,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    CommunityOwnedDate,
    ClosedDate,
    CloseReason,
    ClosureDays,
    AnswerDays,
    CommunityOwnedDays,
    ClosureDaysSinceOwnership,
    ClosureDaysSinceAcceptedAnswer,
    ClosureDaysSinceLastEdit,
    ClosureDaysSinceLastActivity,
    ClosureDaysSinceLastAccess,
    ClosureDaysSinceLastEdit,
    ClosureDaysSinceCreation,
    AnswerDays,
    FavoriteDays,
    ViewDays,
    CommentDays,
    ScoreDays,
    OwnerUserDays,
    LastEditorUserDays,
    AcceptedAnswerDays,
    ParentPostDays,
    CommunityOwnedDays
FROM cte;