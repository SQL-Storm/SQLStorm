WITH QuestionAnswerScores AS (
    SELECT 
        q.Id AS QuestionId, 
        q.Title,
        q.CreationDate AS QuestionCreation,
        q.ViewCount,
        q.Score AS QuestionScore,
        COALESCE(a.Score, 0) AS AnswerScore,
        COALESCE(a.OwnerUserId, -1) AS AnswerOwnerId,
        a.CreationDate AS AnswerCreation,
        u.DisplayName AS QuestionOwner,
        au.DisplayName AS AnswerOwner,
        EXISTS (
            SELECT 1 
            FROM Votes v 
            WHERE v.PostId = q.Id AND v.VoteTypeId = 6
        ) AS QuestionClosed,
        (SELECT COUNT(1) FROM Comments c WHERE c.PostId = q.Id) AS QCommentCount,
        (SELECT COUNT(1) FROM Comments c WHERE c.PostId = COALESCE(q.AcceptedAnswerId, -1)) AS AACCComCount,
        (
            SELECT string_agg(DISTINCT vh.Name, ',')
            FROM PostHistory ph
            LEFT JOIN PostHistoryTypes vh ON ph.PostHistoryTypeId = vh.Id
            WHERE ph.PostId = q.Id AND ph.UserId = q.OwnerUserId AND vh.Name IS NOT NULL
        ) AS OwnerEditHistoryTypes
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN Users au ON au.Id = a.OwnerUserId
    WHERE q.PostTypeId = 1
), RankedQuestions AS (
    SELECT 
        QuestionId,
        Title,
        QuestionCreation,
        ViewCount,
        QuestionScore,
        AnswerScore,
        AnswerOwnerId,
        AnswerCreation,
        QuestionOwner,
        AnswerOwner,
        QuestionClosed,
        QCommentCount,
        AACCComCount,
        OwnerEditHistoryTypes,
        ROW_NUMBER() OVER (PARTITION BY AnswerOwnerId ORDER BY AnswerScore DESC, AnswerCreation) AS RnkPerAnswerer,
        COUNT(*) OVER (PARTITION BY AnswerOwnerId) AS AnswerCountPerUser
    FROM QuestionAnswerScores
)

SELECT
    rq.QuestionId,                             
    rq.Title,                        
    rq.QuestionCreation,                        
    rq.ViewCount,                        
    rq.QuestionScore,                        
    rq.AnswerScore,                        
    ('Q:' || COALESCE(rq.QuestionOwner,'<anonymous>') || '|A:' || COALESCE(rq.AnswerOwner,'<none>')) AS UserPeeks,     
    rq.QuestionClosed,                                 
    rq.QCommentCount,              
    COALESCE(rq.AACCComCount, 0) AS CommentsOnAcceptedAnswer,
    rq.OwnerEditHistoryTypes AS PostHistorySummaryote,
    CASE                         
     WHEN rq.ViewCount > 10000 AND rq.AnswerScore > rq.QuestionScore THEN 'PopularStrongAnswer'                  
     WHEN rq.ViewCount <= 10000 AND rq.AnswerScore < rq.QuestionScore THEN 'LowViewNoAnswerBoost'   
     WHEN rq.QuestionClosed THEN 'LowQualityClose'
     ELSE 'Misc'                
    END AS AnalysisCategory,

    (SELECT MAX(ph.Id)
     FROM PostHistory ph
     WHERE ph.PostId = rq.QuestionId    
           AND (ph.PostHistoryTypeId IN (4,5,6) OR ph.UserId = rq.AnswerOwnerId)
           AND (
              ph.Text LIKE '%error(feed)%' ESCAPE '\'
              OR ph.Comment LIKE '%close%'
              OR ph.Comment IS NULL
           )
    ) AS MostRelevantHistoryId,    

    COALESCE(
       (SELECT AVG(v2.ActivityCt) FROM (
          SELECT COUNT(ph2.Id) AS ActivityCt FROM PostHistory ph2 WHERE ph2.UserId = rq.AnswerOwnerId GROUP BY ph2.RevisionGUID
       ) AS v2),
    0) AS UserPostHistoryActivityGRPAvg,

    DENSE_RANK() OVER (ORDER BY rq.ViewCount DESC, (rq.QuestionScore + rq.AnswerScore) DESC) AS GlobTrendingRank       

 
FROM RankedQuestions rq
LEFT JOIN Users ultr ON ultr.Id = rq.AnswerOwnerId
GROUP BY
    rq.QuestionId,
    rq.Title,
    rq.QuestionCreation,
    rq.ViewCount,
    rq.QuestionScore,
    rq.AnswerScore,
    rq.QuestionOwner,
    rq.AnswerOwner,
    rq.QuestionClosed,
    rq.QCommentCount,
    rq.AACCComCount,
    rq.OwnerEditHistoryTypes,
    rq.AnswerCreation,
    rq.AnswerOwnerId,
    rq.RnkPerAnswerer,
    rq.AnswerCountPerUser,
    ultr.Id,
    ultr.DisplayName;