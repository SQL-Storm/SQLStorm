-- {"query": "1431.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1339} 
WITH QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        COALESCE(p.FavoriteCount,0) AS FavoriteCount,
        STRING_AGG(DISTINCT t.TagName, ',') AS Tags,
        RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScoreAndViews,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgesOwnedByAsker,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadgesOwnedByAsker,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadgesOwnedByAsker,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId = 4) AS LastTitleEditDate,
        EXISTS (
            SELECT 1 FROM PostLinks pl 
            WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
        ) AS HasDuplicateLink,
        -- Window function for average score rank among owner’s questions
        AVG(RANK() OVER (ORDER BY p.Score DESC)) OVER (PARTITION BY u.Id) AS AvgScoreRankForUser
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN LATERAL (
        SELECT TagName FROM unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><')) AS t(TagName)
    ) t ON true
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.CreationDate, u.DisplayName, u.Reputation, 
             p.ViewCount, p.Score, p.AnswerCount, p.FavoriteCount, u.Id
),
TopLimit AS (
    SELECT AVG(FavoriteCount) * 0.75 AS FavThresh FROM QuestionStats
),
HighFavQuestions AS (
    SELECT qs.* 
    FROM QuestionStats qs, TopLimit tl
    WHERE qs.FavoriteCount > tl.FavThresh
),
AnswerCorrelated AS (
    SELECT a.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(case when a.OwnerUserId = q.OwnerUserId then 1 else 0 end) AS AnswersByAsker,
        MAX(COALESCE(vup.UpVotes,0)) AS MaxAnswerOwnerUpvotesMostActive
    FROM Posts a
    INNER JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId=1
    LEFT JOIN LATERAL (
      SELECT COUNT(*) AS UpVotes FROM Votes v 
      WHERE v.PostId = a.Id AND v.VoteTypeId = 2
    ) vup ON true
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId, q.OwnerUserId
),
ComplexPostDetails AS (
    SELECT
        p.Id,
        COALESCE(u.DisplayName, p.OwnerDisplayName, '<anonymous>') ||
            CASE WHEN p.LastEditDate IS NOT NULL 
                 THEN ' (Edited)' ELSE '' END AS OwnerDisplayWithEdit,
        p.Score,
        p.ViewCount,
        COALESCE(xacts.vote_score, 0) AS VoteScoreSum,
        COUNT(DISTINCT c.Id) FILTER (WHERE c.Score > 0) AS PositiveCommentCount,
        MAX(ph.CreationDate) AS LastPostHistoryDate,
        (SELECT COUNT(*) FROM Comments c  
          WHERE c.PostId = p.Id AND c.Text ILIKE '%great%') AS CountCommentsMentioningGreat,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as SeqNumByPostType
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN LATERAL (
       SELECT SUM(CASE vpt.Id WHEN 2 THEN 1 WHEN 3 THEN -1 ELSE 0 END) AS vote_score
       FROM VoteTypes vpt GROUP BY vpt.Id 
       HAVING TRUE
    ) xacts ON true
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, u.DisplayName, p.OwnerDisplayName, p.Score, p.ViewCount, xacts.vote_score, p.LastEditDate, p.PostTypeId
)
SELECT
    hq.Title,
    hq.OwnerName,
    hq.OwnerReputation,
    hq.Tags,
    hq.Score,
    hq.ViewCount,
    hq.FavoriteCount,
    ac.AnswerCount AS Answers,
    ac.AvgAnswerScore,
    ac.AnswersByAsker,
    ac.MaxAnswerScore,
    CASE WHEN hq.HasDuplicateLink THEN 'TRUE' ELSE 'FALSE' END AS IsMarkedDuplicate,
    ps.OwnerDisplayWithEdit,
    ps.VoteScoreSum,
    ps.PositiveCommentCount,
    ps.LastPostHistoryDate,
    ps.CountCommentsMentioningGreat,
    hq.LastTitleEditDate,
    hq.GoldBadgesOwnedByAsker,
    hq.SilverBadgesOwnedByAsker,
    hq.BronzeBadgesOwnedByAsker,
    hq.RankByScoreAndViews,
    hq.AvgScoreRankForUser,
    ps.SeqNumByPostType
FROM HighFavQuestions hq
LEFT JOIN AnswerCorrelated ac ON ac.QuestionId = hq.QuestionId
LEFT JOIN ComplexPostDetails ps ON ps.Id = hq.QuestionId
WHERE 
    (ps.PositiveCommentCount > 3 OR ps.CountCommentsMentioningGreat > 0)
    AND hq.OwnerReputation > 1000
ORDER BY 
    hq.Score DESC,
    ac.MaxAnswerScore DESC,
    ps.PositiveCommentCount DESC,
    hq.ViewCount DESC
LIMIT 100;