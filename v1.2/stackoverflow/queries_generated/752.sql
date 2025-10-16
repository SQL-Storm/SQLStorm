-- {"query": "752.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1772} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        1 AS Level,
        ARRAY[t.TagName] AS Path
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
    UNION ALL
    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        r.Path || t2.TagName
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id <> r.Id AND NOT t2.TagName = ANY(r.Path)
    WHERE t2.IsModeratorOnly = 0 AND t2.IsRequired = 0 AND r.Level < 3
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges,
        RANK() OVER (ORDER BY COUNT(b.Id) DESC, u.Reputation DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.CreationDate AS QuestionCreationDate,
        COUNT(a.Id) AS AnswerCount,
        AVG(COALESCE(a.Score,0)) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore,
        SUM(CASE WHEN a.OwnerUserId = q.OwnerUserId THEN 1 ELSE 0 END) AS AnswersByAsker,
        STRING_AGG(DISTINCT COALESCE(u.DisplayName, 'Anonymous'), ', ') AS AnswererNames,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS QuestionComments,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId IN (SELECT a2.Id FROM Posts a2 WHERE a2.ParentId = q.Id)) AS AnswerComments
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.OwnerUserId, q.Score, q.ViewCount, q.CreationDate
),
TopPostsWithVotes AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.PostTypeId, p.Title, p.Score, p.ViewCount, p.Tags, p.OwnerUserId, p.CreationDate
),
QuestionsWithDuplicateLinks AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        pl.RelatedPostId AS DuplicateOf,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        u.DisplayName AS OwnerName,
        dt.Name AS LinkTypeName,
        CASE WHEN q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM Posts q
    LEFT JOIN PostLinks pl ON q.Id = pl.PostId AND pl.LinkTypeId = 3
    LEFT JOIN LinkTypes dt ON pl.LinkTypeId = dt.Id
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
),
FinalAggregated AS (
    SELECT DISTINCT
        pas.QuestionId,
        pas.Title,
        pas.QuestionScore,
        pas.ViewCount,
        pas.AnswerCount,
        pas.AvgAnswerScore,
        pas.MaxAnswerScore,
        pas.MinAnswerScore,
        pas.AnswersByAsker,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
        ubs.BadgeRank,
        dup.DuplicateOf,
        dup.IsClosed,
        dup.LinkTypeName,
        pas.QuestionComments,
        pas.AnswerComments,
        ts.UpVotes,
        ts.DownVotes,
        ts.FavoriteVotes,
        -- Complex string expression combining tags and user display names
        CONCAT(
            'Tags: ',
            COALESCE(pas.Title, 'No Title'),
            ' | Answers: ', pas.AnswerCount,
            ' | Owner Badges: G', COALESCE(ubs.GoldBadges,0),
            ' S', COALESCE(ubs.SilverBadges,0),
            ' B', COALESCE(ubs.BronzeBadges,0),
            ' | Dup? ', CASE WHEN dup.DuplicateOf IS NOT NULL THEN 'Yes' ELSE 'No' END,
            ' | Closed? ', CASE WHEN dup.IsClosed = 1 THEN 'Yes' ELSE 'No' END
        ) AS SummaryInfo
    FROM PostAnswerStats pas
    LEFT JOIN UserBadgeStats ubs ON pas.OwnerUserId = ubs.UserId
    LEFT JOIN QuestionsWithDuplicateLinks dup ON pas.QuestionId = dup.QuestionId
    LEFT JOIN TopPostsWithVotes ts ON pas.QuestionId = ts.Id
    LEFT JOIN Users u ON pas.OwnerUserId = u.Id
    WHERE pas.AnswerCount > 0
),
RankedResults AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY IsClosed ORDER BY QuestionScore DESC, AnswerCount DESC, TotalBadges DESC) AS RowNumClosedStatus,
        RANK() OVER (ORDER BY QuestionScore DESC, AnswerCount DESC) AS GlobalRank
    FROM FinalAggregated
)
SELECT
    rr.QuestionId,
    rr.Title,
    rr.QuestionScore,
    rr.ViewCount,
    rr.AnswerCount,
    rr.AvgAnswerScore,
    rr.MaxAnswerScore,
    rr.MinAnswerScore,
    rr.AnswersByAsker,
    rr.GoldBadges,
    rr.SilverBadges,
    rr.BronzeBadges,
    rr.TotalBadges,
    rr.BadgeRank,
    rr.DuplicateOf,
    rr.IsClosed,
    rr.LinkTypeName,
    rr.QuestionComments,
    rr.AnswerComments,
    rr.UpVotes,
    rr.DownVotes,
    rr.FavoriteVotes,
    rr.SummaryInfo,
    rr.RowNumClosedStatus,
    rr.GlobalRank,
    -- Correlated subquery: count of other questions by same owner with higher score
    (SELECT COUNT(*)
     FROM Posts p2
     WHERE p2.PostTypeId = 1
       AND p2.OwnerUserId = rr.QuestionId
       AND p2.Score > rr.QuestionScore
    ) AS HigherScoredQuestionsByOwner,
    -- NULL logic with COALESCE and CASE
    CASE
        WHEN rr.IsClosed = 1 THEN 'Closed'
        WHEN rr.DuplicateOf IS NOT NULL THEN 'Duplicate'
        ELSE 'Open'
    END AS PostStatus,
    -- Window function: cumulative sum of views over partition by IsClosed
    SUM(rr.ViewCount) OVER (PARTITION BY rr.IsClosed ORDER BY rr.QuestionScore DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeViewsByClosedStatus
FROM RankedResults rr
WHERE rr.RowNumClosedStatus <= 10
ORDER BY rr.IsClosed, rr.GlobalRank
LIMIT 50;
