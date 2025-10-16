-- {"query": "748.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2066} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        t.Count,
        r.TagPath || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id <> r.Id AND t.Count < r.Count AND NOT t.TagName = ANY(r.TagPath)
    WHERE t.IsModeratorOnly = 0
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN b.TagBased = 1 THEN b.Name END) AS DistinctTagBadges,
        AVG(EXTRACT(EPOCH FROM (NOW() - u.CreationDate))/86400) FILTER (WHERE u.CreationDate IS NOT NULL) AS AccountAgeDays,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostComplexStats AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        COALESCE(pl.DuplicateCount, 0) AS DuplicateLinks,
        COALESCE(v.UpVotes, 0) AS UpVotes,
        COALESCE(v.DownVotes, 0) AS DownVotes,
        COALESCE(c.CommentCount, 0) AS CommentCount,
        -- Complex tag count approximation by counting '><' + 1 in Tags string, handling NULL
        CASE 
            WHEN p.Tags IS NULL THEN 0
            ELSE array_length(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><'), 1)
        END AS TagCount
    FROM Posts p
    LEFT JOIN (
        SELECT
            pl.PostId,
            COUNT(*) AS DuplicateCount
        FROM PostLinks pl
        WHERE pl.LinkTypeId = 3
        GROUP BY pl.PostId
    ) pl ON pl.PostId = p.Id
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY PostId
    ) v ON v.PostId = p.Id
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = p.Id
),
RankedAnswers AS (
    SELECT
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate DESC) AS RecentRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
TopQuestions AS (
    SELECT
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score,
        q.OwnerUserId,
        q.Tags,
        q.ViewCount,
        q.AnswerCount,
        q.AcceptedAnswerId,
        u.DisplayName AS OwnerName,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.ReputationRank
    FROM Posts q
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN UserBadgeStats ub ON ub.UserId = q.OwnerUserId
    WHERE q.PostTypeId = 1
      AND q.Score > 10
      AND q.AnswerCount > 0
      AND q.ClosedDate IS NULL
),
QuestionWithTopAnswer AS (
    SELECT
        q.*,
        a.Id AS TopAnswerId,
        a.Score AS TopAnswerScore,
        a.OwnerUserId AS TopAnswerOwnerId,
        u.DisplayName AS TopAnswerOwnerName,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC) AS AnswerRank
    FROM TopQuestions q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
),
FinalAggregated AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerName,
        q.GoldBadges,
        q.SilverBadges,
        q.BronzeBadges,
        q.ReputationRank,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.Tags,
        a.TopAnswerId,
        a.TopAnswerScore,
        a.TopAnswerOwnerName,
        -- Calculate string length of title and tags combined with some expression for complexity
        LENGTH(COALESCE(q.Title, '')) + LENGTH(COALESCE(q.Tags, '')) AS TitleTagLength,
        -- Conditional expression to classify question popularity
        CASE 
            WHEN q.ViewCount > 10000 THEN 'Very High'
            WHEN q.ViewCount BETWEEN 5000 AND 10000 THEN 'High'
            WHEN q.ViewCount BETWEEN 1000 AND 4999 THEN 'Moderate'
            ELSE 'Low'
        END AS PopularityCategory,
        -- Correlated subquery for counting comments on question
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS QuestionCommentCount,
        -- Correlated subquery for counting distinct users who have commented on question
        (SELECT COUNT(DISTINCT COALESCE(c.UserId, -1)) FROM Comments c WHERE c.PostId = q.Id) AS DistinctCommenters,
        -- Window function for cumulative sum of scores over questions ordered by score descending
        SUM(q.Score) OVER (ORDER BY q.Score DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeQuestionScore,
        -- Boolean expression using NULL logic on badges
        CASE WHEN q.GoldBadges IS NULL OR q.GoldBadges = 0 THEN TRUE ELSE FALSE END AS NoGoldBadges,
        -- Complex predicate involving tags: check if question contains any tag in RecursiveTagHierarchy
        EXISTS (
            SELECT 1 FROM RecursiveTagHierarchy r
            WHERE q.Tags IS NOT NULL AND POSITION(r.TagName IN q.Tags) > 0
        ) AS HasRequiredTag,
        -- Left join on PostHistory to detect if question was ever closed and reopened (outer join + null logic)
        ph.ClosedCount,
        ph.ReopenCount
    FROM QuestionWithTopAnswer q
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(CASE WHEN PostHistoryTypeId = 10 THEN 1 END) AS ClosedCount,
            COUNT(CASE WHEN PostHistoryTypeId = 11 THEN 1 END) AS ReopenCount
        FROM PostHistory
        WHERE PostHistoryTypeId IN (10, 11)
        GROUP BY PostId
    ) ph ON ph.PostId = q.Id
    WHERE a.AnswerRank = 1 OR a.AnswerRank IS NULL
)
SELECT
    QuestionId,
    Title,
    OwnerName,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    ReputationRank,
    QuestionScore,
    ViewCount,
    AnswerCount,
    Tags,
    TopAnswerId,
    TopAnswerScore,
    TopAnswerOwnerName,
    TitleTagLength,
    PopularityCategory,
    QuestionCommentCount,
    DistinctCommenters,
    CumulativeQuestionScore,
    NoGoldBadges,
    HasRequiredTag,
    COALESCE(ClosedCount, 0) AS TimesClosed,
    COALESCE(ReopenCount, 0) AS TimesReopened
FROM FinalAggregated
ORDER BY CumulativeQuestionScore DESC
LIMIT 100

UNION

SELECT
    Id AS QuestionId,
    Title,
    OwnerDisplayName AS OwnerName,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    NULL AS ReputationRank,
    Score AS QuestionScore,
    ViewCount,
    AnswerCount,
    Tags,
    NULL AS TopAnswerId,
    NULL AS TopAnswerScore,
    NULL AS TopAnswerOwnerName,
    LENGTH(COALESCE(Title, '')) + LENGTH(COALESCE(Tags, '')) AS TitleTagLength,
    CASE 
        WHEN ViewCount > 10000 THEN 'Very High'
        WHEN ViewCount BETWEEN 5000 AND 10000 THEN 'High'
        WHEN ViewCount BETWEEN 1000 AND 4999 THEN 'Moderate'
        ELSE 'Low'
    END AS PopularityCategory,
    0 AS QuestionCommentCount,
    0 AS DistinctCommenters,
    0 AS CumulativeQuestionScore,
    TRUE AS NoGoldBadges,
    FALSE AS HasRequiredTag,
    0 AS TimesClosed,
    0 AS TimesReopened
FROM Posts
WHERE PostTypeId = 1
  AND Score <= 10
ORDER BY QuestionScore DESC
LIMIT 50;
