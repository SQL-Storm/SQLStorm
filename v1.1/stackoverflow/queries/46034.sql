WITH TopUsersByReputation AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as RepRank
    FROM Users u
    WHERE u.Reputation > 10000
    LIMIT 1000
),
QuestionMetrics AS (
    SELECT 
        p.Id as QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(a.Id, 0) as AcceptedAnswerId,
        COALESCE(a.Score, 0) as AcceptedAnswerScore,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownVotes,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.Id END) as LinkedCount,
        COUNT(DISTINCT CASE WHEN pl2.LinkTypeId = 3 THEN pl2.Id END) as DuplicateCount
    FROM Posts p
    LEFT JOIN Posts a ON p.AcceptedAnswerId = a.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN PostLinks pl2 ON p.Id = pl2.RelatedPostId AND pl2.LinkTypeId = 3
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= '2020-01-01'
        AND p.Score >= 5
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, 
             p.AnswerCount, p.CommentCount, p.FavoriteCount, a.Id, a.Score
),
UserActivityStats AS (
    SELECT 
        tu.Id as UserId,
        tu.DisplayName,
        tu.Reputation,
        COUNT(DISTINCT qm.QuestionId) as QuestionsAsked,
        AVG(qm.Score) as AvgQuestionScore,
        SUM(qm.ViewCount) as TotalViews,
        COUNT(DISTINCT ans.Id) as AnswersProvided,
        AVG(ans.Score) as AvgAnswerScore,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
        COUNT(DISTINCT c.Id) as CommentsMade,
        COUNT(DISTINCT ph.Id) as EditsMade,
        SUM(CASE WHEN qm.AcceptedAnswerId > 0 THEN 1 ELSE 0 END) as QuestionsWithAcceptedAnswer
    FROM TopUsersByReputation tu
    LEFT JOIN QuestionMetrics qm ON tu.Id = qm.OwnerUserId
    LEFT JOIN Posts ans ON tu.Id = ans.OwnerUserId AND ans.PostTypeId = 2
    LEFT JOIN Badges b ON tu.Id = b.UserId
    LEFT JOIN Comments c ON tu.Id = c.UserId
    LEFT JOIN PostHistory ph ON tu.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY tu.Id, tu.DisplayName, tu.Reputation
),
TagPerformance AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT qm.QuestionId) as QuestionCount,
        AVG(qm.Score) as AvgScore,
        AVG(qm.AnswerCount) as AvgAnswerCount,
        AVG(qm.ViewCount) as AvgViewCount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qm.Score) as MedianScore,
        MAX(qm.Score) as MaxScore,
        SUM(qm.UpVotes) as TotalUpVotes,
        SUM(qm.DownVotes) as TotalDownVotes
    FROM Tags t
    CROSS JOIN LATERAL (
        SELECT qm.*
        FROM QuestionMetrics qm
        JOIN Posts p ON qm.QuestionId = p.Id
        WHERE p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
        LIMIT 500
    ) qm
    WHERE t.Count > 100
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT qm.QuestionId) >= 10
)
SELECT 
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionsAsked,
    ROUND(CAST(uas.AvgQuestionScore AS DECIMAL), 2) as AvgQuestionScore,
    uas.TotalViews,
    uas.AnswersProvided,
    ROUND(CAST(uas.AvgAnswerScore AS DECIMAL), 2) as AvgAnswerScore,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    uas.CommentsMade,
    uas.EditsMade,
    ROUND(100.0 * uas.QuestionsWithAcceptedAnswer / NULLIF(uas.QuestionsAsked, 0), 2) as AcceptanceRate,
    STRING_AGG(tp.TagName, ', ') as TopTags,
    AVG(tp.AvgScore) as AvgScoreInTopTags
FROM UserActivityStats uas
CROSS JOIN LATERAL (
    SELECT 
        tp.*,
        ROW_NUMBER() OVER (ORDER BY tp.QuestionCount DESC) as tp_rank
    FROM TagPerformance tp
    JOIN Posts p ON p.Tags LIKE '%' || '<' || tp.TagName || '>' || '%'
    JOIN QuestionMetrics qm ON p.Id = qm.QuestionId
    WHERE qm.OwnerUserId = uas.UserId
) tp
WHERE uas.QuestionsAsked >= 5
    AND uas.AnswersProvided >= 5
    AND tp.tp_rank <= 5
GROUP BY uas.UserId, uas.DisplayName, uas.Reputation, uas.QuestionsAsked, 
         uas.AvgQuestionScore, uas.TotalViews, uas.AnswersProvided, 
         uas.AvgAnswerScore, uas.GoldBadges, uas.SilverBadges, 
         uas.BronzeBadges, uas.CommentsMade, uas.EditsMade, uas.QuestionsWithAcceptedAnswer
ORDER BY uas.Reputation DESC, uas.TotalViews DESC
LIMIT 100;