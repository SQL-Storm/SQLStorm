-- {"query": "1116.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1563} 

WITH RankedAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank,
        COUNT(*) OVER (PARTITION BY a.ParentId) AS TotalAnswers,
        CASE 
            WHEN a.Score >= 10 THEN 'High'
            WHEN a.Score BETWEEN 1 AND 9 THEN 'Medium'
            WHEN a.Score <= 0 THEN 'Low'
            ELSE 'Unknown'
        END AS ScoreCategory,
        COALESCE(u.DisplayName, 'Unknown') AS AnswererName,
        COALESCE(NULLIF(u.Location,''), 'Location Unknown') AS Location
    FROM
        Posts a
        LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE
        a.PostTypeId = 2 -- Answers only
        AND a.Score IS NOT NULL
),
QuestionWithStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.AcceptedAnswerId,
        COALESCE(usr.DisplayName, 'ANONYMOUS') AS QuestionOwner,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS CommentCountOnQuestion,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) AS DownVotes,
        COALESCE(usr.Location, 'Unknown') AS OwnerLocation
    FROM
        Posts q
        LEFT JOIN Users usr ON q.OwnerUserId = usr.Id
    WHERE
        q.PostTypeId = 1 -- Questions only
),
AnswerAggregates AS (
    SELECT
        ras.QuestionId,
        COUNT(*) AS TotalAnswers,
        SUM(CASE WHEN ras.ScoreCategory = 'High' THEN 1 ELSE 0 END) AS HighScoringAnswers,
        AVG(ras.Score) AS AvgAnswerScore,
        MAX(ras.Score) AS MaxAnswerScore,
        MIN(ras.Score) AS MinAnswerScore
    FROM RankedAnswers ras
    GROUP BY ras.QuestionId
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges,
        MAX(b.Date) AS MostRecentBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
TopRelatedDuplicates AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        pl.Id AS LinkId,
        rt.Name AS LinkTypeName,
        pq.Score AS QuestionScore,
        pr.Score AS RelatedQuestionScore
    FROM
        PostLinks pl
        INNER JOIN LinkTypes rt ON pl.LinkTypeId = rt.Id
        INNER JOIN Posts pq ON pl.PostId = pq.Id
        INNER JOIN Posts pr ON pl.RelatedPostId = pr.Id
    WHERE
        rt.Name = 'Duplicate' AND pq.PostTypeId = 1 AND pr.PostTypeId = 1
),
CombinedQuestionInfo AS (
    SELECT
        qws.QuestionId,
        qws.Title,
        qws.Tags,
        qws.QuestionOwner,
        qws.Score,
        qws.ViewCount,
        qws.CreationDate,
        qws.AcceptedAnswerId,
        aggr.TotalAnswers,
        aggr.HighScoringAnswers,
        aggr.AvgAnswerScore,
        aggr.MaxAnswerScore,
        aggr.MinAnswerScore,
        qws.CommentCountOnQuestion,
        qws.UpVotes,
        qws.DownVotes,
        qws.OwnerLocation,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.TotalBadges,
        ubs.MostRecentBadgeDate
    FROM QuestionWithStats qws
    LEFT JOIN AnswerAggregates aggr ON qws.QuestionId = aggr.QuestionId
    LEFT JOIN UserBadgeStats ubs ON qws.OwnerUserId = ubs.UserId
)
SELECT
    cqi.QuestionId,
    cqi.Title,
    LEFT(cqi.Tags, 255) AS SampleTags,
    cqi.QuestionOwner,
    CONCAT(
        'Score: ', cqi.Score, 
        ', Views: ', cqi.ViewCount, 
        ', Answers: ', COALESCE(cqi.TotalAnswers, 0), 
        ', Comments: ', cqi.CommentCountOnQuestion
    ) AS QuestionSummary,
    CONCAT(
        'Answer Scores [Avg: ', ROUND(COALESCE(cqi.AvgAnswerScore,0),2),
        ', Max: ', COALESCE(cqi.MaxAnswerScore,0),
        ', Min: ', COALESCE(cqi.MinAnswerScore,0),
        ', High Scoring: ', COALESCE(cqi.HighScoringAnswers, 0), ']'
    ) AS AnswerScoreStats,
    CONCAT(
        'Owner Badges [Gold: ', COALESCE(cqi.GoldBadges,0),
        ', Silver: ', COALESCE(cqi.SilverBadges,0),
        ', Bronze: ', COALESCE(cqi.BronzeBadges,0),
        ', Total: ', COALESCE(cqi.TotalBadges,0), ']'
    ) AS OwnerBadgeStats,
    CASE WHEN plr.LinkId IS NOT NULL THEN CONCAT('Duplicate Of QuestionId:', plr.RelatedPostId, ' Score:', plr.RelatedQuestionScore) ELSE 'No duplicate links' END AS DuplicateInfo,
    RANK() OVER (ORDER BY cqi.Score DESC NULLS LAST, cqi.ViewCount DESC NULLS LAST) AS QuestionRank,
    EXTRACT(YEAR FROM AGE(NOW(), cqi.CreationDate)) AS YearsSinceAsked,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = cqi.QuestionId AND c.Text LIKE '%SQL%') AS SQLCommentsCount,
    EXISTS (
        SELECT 1 FROM Votes v 
        WHERE v.PostId = cqi.QuestionId 
          AND v.VoteTypeId = 8 -- BountyStart
          AND v.CreationDate > cqi.CreationDate
    ) AS HasBountyEverStarted
FROM
    CombinedQuestionInfo cqi
    LEFT JOIN LATERAL (
        SELECT *
        FROM TopRelatedDuplicates plr
        WHERE plr.PostId = cqi.QuestionId
        ORDER BY plr.CreationDate DESC
        LIMIT 1
    ) plr ON TRUE
WHERE
    COALESCE(cqi.TotalAnswers,0) > 3
    AND cqi.UpVotes > cqi.DownVotes
    AND cqi.QuestionOwner IS NOT NULL
ORDER BY
    cqi.Score DESC NULLS LAST,
    cqi.ViewCount DESC NULLS LAST
LIMIT 100;
