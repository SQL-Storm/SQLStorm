-- {"query": "1325.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1563} 
WITH RankedAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.CreationDate,
        a.Score,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank,
        COUNT(*) OVER (PARTITION BY a.ParentId) AS TotalAnswers
    FROM Posts a
    WHERE a.PostTypeId = 2
),
QuestionDetails AS (
    SELECT
        q.Id,
        q.Title,
        q.Tags,
        q.AcceptedAnswerId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.ClosedDate,
        u.DisplayName AS AskerName,
        COALESCE(u.Reputation,0) AS AskerReputation,
        STRING_AGG(b.Name || ' (' || CASE b.Class WHEN 1 THEN 'Gold' WHEN 2 THEN 'Silver' WHEN 3 THEN 'Bronze' END || ')'::varchar, ', ' ORDER BY b.Date DESC) AS AskerBadges,
        STRING_AGG(pht.Name, ', ' ORDER BY pht.Id) AS EditTypes
    FROM Posts q
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.PostId = q.Id AND ph.UserId = q.OwnerUserId
    LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.Tags, q.AcceptedAnswerId, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, q.ClosedDate, u.DisplayName, u.Reputation
),
LinkInfo AS (
    SELECT DISTINCT 
        pl.PostId,
        ARRAY_AGG(DISTINCT lt.Name) FILTER (WHERE lt.Name IS NOT NULL) AS LinkTypes
    FROM PostLinks pl
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
),
CommentsStats AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'unknown'), ', ') AS CommentAuthors
    FROM Comments c
    GROUP BY c.PostId
),
AnswerRanks AS (
    SELECT
        q.Id AS QuestionId,
        STRING_AGG(CONCAT(
            'Rank ', ra.AnswerRank, ': AnswerId=', ra.AnswerId, 
            ', Score=', ra.Score,
            ', Created=', TO_CHAR(ra.CreationDate, 'YYYY-MM-DD'), 
            ', RelScore=', (ra.Score::decimal / NULLIF(rd.MaxScore,0))::numeric(6,4)
        ), '; ' ORDER BY ra.AnswerRank) AS AnswersRankSummary
    FROM RankedAnswers ra
    JOIN (
        SELECT ParentId, MAX(Score) AS MaxScore FROM RankedAnswers GROUP BY ParentId
    ) rd ON ra.ParentId = rd.ParentId
    JOIN Posts q ON q.Id = ra.ParentId
    WHERE ra.AnswerRank <= 3
    GROUP BY q.Id
),
PostsWithDuplicates AS (
    SELECT
        pl.PostId AS OriginalPostId,
        COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount,
        STRING_AGG(DISTINCT CAST(pl.RelatedPostId AS varchar), ', ') FILTER (WHERE pl.LinkTypeId = 3) AS DuplicatePostIds
    FROM PostLinks pl
    GROUP BY pl.PostId
),
QuestionsCTE AS (
    SELECT
        q.Id,
        q.Title,
        COALESCE(q.Tags, '') AS Tags,
        q.AcceptedAnswerId,
        qu.AnswerCount,
        qu.FavoriteCount,
        q.Score AS QScore,
        q.ViewCount,
        q.ClosedDate,
        qi.LinkTypes,
        cs.CommentCount,
        cs.AvgCommentScore,
        cs.LastCommentDate,
        cs.CommentAuthors,
        pd.DuplicateCount,
        pd.DuplicatePostIds,
        ar.AnswersRankSummary,
        CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        COALESCE(usr.Reputation,0) AS OwnerReputation,
        CASE WHEN q.ClosedDate IS NULL THEN 0 ELSE 1 END AS IsClosed
    FROM Posts q
    LEFT JOIN QuestionDetails qu ON qu.Id = q.Id
    LEFT JOIN LinkInfo qi ON qi.PostId = q.Id
    LEFT JOIN CommentsStats cs ON cs.PostId = q.Id
    LEFT JOIN PostsWithDuplicates pd ON pd.OriginalPostId = q.Id
    LEFT JOIN AnswerRanks ar ON ar.QuestionId = q.Id
    LEFT JOIN Users usr ON usr.Id = q.OwnerUserId
    WHERE q.PostTypeId = 1
)
SELECT
    qc.Id AS QuestionId,
    qc.Title,
    LENGTH(qc.Tags) AS TagStringLength,
    qc.Tags,
    qc.AnswerCount,
    qc.FavoriteCount,
    qc.QScore,
    qc.ViewCount,
    qc.IsClosed,
    qc.ClosedDate,
    qc.LinkTypes,
    qc.CommentCount,
    qc.AvgCommentScore,
    qc.LastCommentDate,
    qc.CommentAuthors,
    qc.DuplicateCount,
    qc.DuplicatePostIds,
    qc.AnswersRankSummary,
    qc.HasAcceptedAnswer,
    qc.OwnerReputation,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = qc.Id AND b.Name ILIKE '%legendary%') THEN 'Legendary Owner'
        WHEN qc.OwnerReputation > 100000 THEN 'High Rep Owner'
        ELSE 'Regular Owner'
    END AS OwnerClass,
    -- Complex string manipulation and conditional expressions
    CONCAT(
        'Q#', qc.Id, ' @', TO_CHAR(qc.ClosedDate, 'YYYY-MM-DD'),
        ' [Score:', qc.QScore, 
        ', Views:', qc.ViewCount, 
        ', TagsLen:', LENGTH(qc.Tags),
        '] Closed? ', CASE qc.IsClosed WHEN 1 THEN 'Yes' ELSE 'No' END
    ) AS Summary,
    -- Dynamic CASE with NULL logic
    CASE 
        WHEN qc.FavoriteCount IS NULL OR qc.FavoriteCount = 0 THEN 'No Favorites'
        WHEN qc.FavoriteCount > qc.AnswerCount THEN 'Very Popular'
        ELSE 'Moderate Interest'
    END AS PopularityFlag,
    -- Correlated subquery with EXISTS
    EXISTS (
        SELECT 1 FROM Votes v 
        WHERE v.PostId = qc.Id AND v.VoteTypeId = 2 AND v.CreationDate > NOW() - INTERVAL '30 days'
        LIMIT 1
    ) AS RecentUpvoted
FROM QuestionsCTE qc
WHERE (
    qc.QScore > 10 OR
    qc.FavoriteCount > 5 OR
    qc.ViewCount > 1000
) AND (
    qc.Tags LIKE '%<sql>%' OR
    qc.Tags LIKE '%<performance>%' OR
    qc.Tags LIKE '%<optimization>%'
)
ORDER BY qc.QScore DESC, qc.ViewCount DESC, qc.Id
LIMIT 50;