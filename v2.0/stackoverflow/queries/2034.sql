-- {"query": "2034.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1513}
WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE

    UNION ALL

    SELECT 
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        rth.Level + 1
    FROM Tags child
    JOIN Posts p ON child.ExcerptPostId = p.Id
    JOIN RecursiveTagHierarchy rth ON rth.Id = child.Id AND rth.Level < 3
), 

UserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(b.Date) DESC NULLS LAST) AS LatestBadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),

PostScoreStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Tags,
        LEAST(p.Score * 1.0 / GREATEST(p.ViewCount, 1), 10) AS ScorePerView,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentPostRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),

AcceptedAnswerInfo AS (
    SELECT 
        q.Id AS QuestionId,
        ans.Id AS AcceptedAnswerId,
        ans.OwnerUserId AS AcceptedAnswerOwnerId,
        ans.Score AS AcceptedAnswerScore
    FROM Posts q
    LEFT JOIN Posts ans ON q.AcceptedAnswerId = ans.Id
    WHERE q.PostTypeId = 1 AND q.AcceptedAnswerId IS NOT NULL
),

UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        SUM(vb.VoteCount) AS TotalVotesCast,
        MIN(u.CreationDate) OVER () AS EarliestUser,
        MAX(u.LastAccessDate) OVER () AS LatestAccessDate,
        MAX(vb.LastVoteDate) AS LastVoteDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRankByReputation
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN (
        SELECT 
            v.UserId,
            COUNT(v.Id) AS VoteCount,
            MAX(v.CreationDate) AS LastVoteDate
        FROM Votes v
        GROUP BY v.UserId
    ) vb ON vb.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),

ComplexPostAnalysis AS (
    SELECT 
        ps.Id AS PostId,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.CreationDate,
        ps.Score,
        ps.Tags,
        -- Extract first tag or NULL: replace angle brackets then split on space
        split_part(regexp_replace(ps.Tags, '[<>]', ' ', 'g'), ' ', 1) AS FirstTag,
        -- Length of body in chars
        length(p.Body) AS BodyLength,
        -- Calculation including null-safe avg comment length for post
        COALESCE((
            SELECT AVG(length(c.Text))
            FROM Comments c
            WHERE c.PostId = ps.Id
        ), 0) AS AvgCommentLength,
        -- Window function: cumulative count posts per user ordered by creation date
        COUNT(*) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS PostsTillNow,
        -- Null logic: Flag posts with no owner or with low score and no accepted answer
        CASE 
            WHEN ps.OwnerUserId IS NULL OR ps.OwnerUserId = -1 THEN 'Orphan'
            WHEN ps.Score < 0 AND NOT EXISTS (
                SELECT 1 FROM AcceptedAnswerInfo aai WHERE aai.QuestionId = ps.Id
            ) THEN 'LowScoreNoAccepted'
            ELSE 'Normal'
        END AS PostQualityFlag
    FROM Posts ps
    LEFT JOIN Posts p ON p.Id = ps.Id
    GROUP BY
        ps.Id,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.CreationDate,
        ps.Score,
        ps.Tags,
        split_part(regexp_replace(ps.Tags, '[<>]', ' ', 'g'), ' ', 1),
        p.Body
),

FinalSelectedPosts AS (
    SELECT 
        cp.PostId,
        cp.PostTypeId,
        u.DisplayName AS OwnerName,
        cp.CreationDate,
        cp.Score,
        cp.FirstTag,
        cp.BodyLength,
        cp.AvgCommentLength,
        cp.PostsTillNow,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ua.Reputation,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        cp.PostQualityFlag,
        CASE 
            WHEN cp.PostQualityFlag = 'Orphan' THEN 0
            ELSE 1
        END AS IsValidPost,
        ROW_NUMBER() OVER (PARTITION BY cp.PostTypeId ORDER BY cp.Score DESC, cp.CreationDate DESC) AS PostRankByType
    FROM ComplexPostAnalysis cp
    LEFT JOIN Users u ON u.Id = cp.OwnerUserId
    LEFT JOIN UserBadgeSummary ub ON ub.UserId = cp.OwnerUserId
    LEFT JOIN UserActivityWindow ua ON ua.UserId = cp.OwnerUserId
    WHERE cp.PostsTillNow > 5
)

SELECT * FROM FinalSelectedPosts
WHERE PostRankByType <= 10

UNION ALL

SELECT 
    p.Id AS PostId,
    p.PostTypeId,
    u.DisplayName AS OwnerName,
    p.CreationDate,
    p.Score,
    NULL AS FirstTag,
    length(p.Body) AS BodyLength,
    0 AS AvgCommentLength,
    1 AS PostsTillNow,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS Reputation,
    0 AS QuestionsPosted,
    0 AS AnswersPosted,
    0 AS CommentsMade,
    'Normal' AS PostQualityFlag,
    1 AS IsValidPost,
    NULL AS PostRankByType
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 3
  AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 3)
ORDER BY PostTypeId, Score DESC, CreationDate DESC
LIMIT 5;