-- {"query": "2137.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1667}
WITH RECURSIVE RecursiveUserHierarchy AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        1 AS Level,
        CAST(NULL AS INTEGER) AS ManagerId
    FROM Users u 
    WHERE u.Id = (SELECT MIN(Id) FROM Users)
    UNION ALL
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        ruh.Level + 1,
        ruh.Id
    FROM Users u
    JOIN RecursiveUserHierarchy ruh ON u.Id > ruh.Id
    WHERE ruh.Level < 5
),
TopScoringAnswerForRecentQuestions AS (
    SELECT p.Id AS QuestionId, p.Title, p.CreationDate AS QuestionCreation,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        row_number() OVER(PARTITION BY p.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS rn
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1 AND p.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '90' DAY)
),
UserBadgeStats AS (
    SELECT b.UserId, 
        count(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        count(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        count(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        count(DISTINCT b.Name) AS DistinctBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserEngagement AS (
    SELECT u.Id, u.DisplayName, 
        COALESCE(SUM(p.ViewCount),0) AS TotalViews,
        COALESCE(SUM(p.Score),0) AS TotalPostScore,
        COALESCE(COUNT(c.Id),0) AS TotalComments,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVotesReceived,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVotesReceived
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
QuestionsWithComplexPredicates AS (
    SELECT p.Id, p.Title, p.Tags, p.Score, p.ViewCount, p.CreationDate,
        array_length(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><'),1) AS TagCount,
        CASE 
            WHEN p.Score > 10 AND p.ViewCount > 1000 THEN 'Hot'
            WHEN p.Score BETWEEN 5 AND 10 THEN 'Trending'
            ELSE 'Regular'
        END AS PopularityStatus,
        EXISTS (
            SELECT 1 FROM Votes v2 WHERE v2.PostId = p.Id AND v2.VoteTypeId = 5 AND v2.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY)
        ) AS HasRecentFavorite,
        COALESCE(p.AnswerCount,0) AS AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 1
),
DuplicatesAndLinkedPosts AS (
    SELECT DISTINCT pl.PostId, pl.RelatedPostId, lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId AND lt.Name IN ('Linked','Duplicate')
),
QuestionCloseReasonStats AS (
    SELECT cht.Name AS CloseReason, COUNT(*) AS ClosedCount
    FROM PostHistory ph
    JOIN PostHistoryTypes chtp ON ph.PostHistoryTypeId = chtp.Id
    JOIN CloseReasonTypes cht ON CAST(ph.Comment AS INTEGER) = cht.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY cht.Name
    ORDER BY ClosedCount DESC
),
RankedAnswersWithWindow AS (
    SELECT a.Id, a.ParentId AS QuestionId, a.Score, 
        rank() OVER(PARTITION BY a.ParentId ORDER BY a.Score DESC) AS ScoreRank,
        dense_rank() OVER(PARTITION BY a.ParentId ORDER BY a.CreationDate ASC) AS OldestRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
AnswerToQuestionCorrelation AS (
    SELECT q.Id AS QuestionId, q.Title, a.Id AS AnswerId, a.Score AS AnswerScore,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS AnswerComments,
        (SELECT MAX(p.Score) FROM Posts p WHERE p.ParentId = q.Id AND p.PostTypeId = 2) AS MaxAnswerScore,
        q.AnswerCount
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
FinalAggregate AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(us.GoldBadges,0) AS GoldBadges,
        COALESCE(us.SilverBadges,0) AS SilverBadges,
        COALESCE(us.BronzeBadges,0) AS BronzeBadges,
        COALESCE(ue.TotalViews,0) AS TotalViews,
        COALESCE(ue.TotalPostScore,0) AS TotalPostScore,
        COALESCE(ue.TotalComments,0) AS TotalComments,
        COALESCE(ue.UpVotesReceived,0) AS UpVotesReceived,
        COALESCE(ue.DownVotesReceived,0) AS DownVotesReceived,
        q.PopularityStatus,
        q.TagCount,
        q.HasRecentFavorite,
        q.AnswerCount,
        qc.ClosedCount,
        max(r.ScoreRank) FILTER (WHERE r.ScoreRank <= 3) AS Top3AnswerRank,
        avg(r.Score) FILTER (WHERE r.ScoreRank <= 3) AS AvgTop3AnswerScore,
        sum(CASE WHEN r.ScoreRank = 1 THEN 1 ELSE 0 END) AS FirstRankCount
    FROM Users u
    LEFT JOIN UserBadgeStats us ON us.UserId = u.Id
    LEFT JOIN UserEngagement ue ON ue.Id = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN QuestionsWithComplexPredicates q ON q.Id = p.Id
    LEFT JOIN QuestionCloseReasonStats qc ON 1=1
    LEFT JOIN RankedAnswersWithWindow r ON r.QuestionId = p.Id
    GROUP BY u.Id, u.DisplayName, COALESCE(us.GoldBadges,0), COALESCE(us.SilverBadges,0), COALESCE(us.BronzeBadges,0), COALESCE(ue.TotalViews,0), COALESCE(ue.TotalPostScore,0), COALESCE(ue.TotalComments,0), COALESCE(ue.UpVotesReceived,0), COALESCE(ue.DownVotesReceived,0), q.PopularityStatus, q.TagCount, q.HasRecentFavorite, q.AnswerCount, qc.ClosedCount
    HAVING COALESCE(us.GoldBadges, 0) + COALESCE(us.SilverBadges, 0) + COALESCE(us.BronzeBadges, 0) > 0
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.GoldBadges, fa.SilverBadges, fa.BronzeBadges,
    fa.TotalViews, fa.TotalPostScore, fa.TotalComments,
    fa.UpVotesReceived, fa.DownVotesReceived,
    fa.PopularityStatus, fa.TagCount, fa.HasRecentFavorite, fa.AnswerCount,
    fa.ClosedCount,
    fa.Top3AnswerRank, fa.AvgTop3AnswerScore, fa.FirstRankCount,
    CASE WHEN fa.TotalPostScore > 0 THEN CAST((fa.UpVotesReceived - fa.DownVotesReceived) AS DOUBLE PRECISION)/fa.TotalPostScore ELSE NULL END AS UpDownRatio,
    CASE WHEN fa.TagCount > 0 THEN CAST(fa.TotalViews AS NUMERIC)/fa.TagCount ELSE NULL END AS ViewsPerTag
FROM FinalAggregate fa
WHERE fa.TotalViews > 1000 AND fa.AvgTop3AnswerScore IS NOT NULL AND fa.Top3AnswerRank IS NOT NULL
ORDER BY fa.GoldBadges DESC, fa.AvgTop3AnswerScore DESC, fa.TotalViews DESC
LIMIT 100;